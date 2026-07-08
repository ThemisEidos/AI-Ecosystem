"""
COOPER Signal gateway (Step 12).

Long-polls a local signal-cli-rest-api container for incoming Signal
messages, filters by sender allowlist (fail closed), routes each message
through main._chat_core, and replies via /v2/send.

Open workshop ONLY (spec §5): messages traverse a remotely reachable
channel, so the gateway must never front the Private workshop.
"""
import asyncio
import os
from dataclasses import dataclass, field
from typing import Awaitable, Callable, List, Optional, Tuple

import httpx

_ERROR_BACKOFF = 10  # seconds after a failed poll


@dataclass
class GatewayConfig:
    api_url: str
    number: str
    allowed_senders: frozenset = field(default_factory=frozenset)
    poll_timeout: int = 20


def load_config(env: Optional[dict] = None) -> Optional[GatewayConfig]:
    """None unless api_url, number, AND a non-empty allowlist are configured."""
    e = os.environ if env is None else env
    api_url = (e.get("SIGNAL_API_URL") or "").strip().rstrip("/")
    number  = (e.get("SIGNAL_NUMBER") or "").strip()
    senders = frozenset(
        s.strip() for s in (e.get("SIGNAL_ALLOWED_SENDERS") or "").split(",") if s.strip()
    )
    if not api_url or not number or not senders:
        return None
    return GatewayConfig(api_url=api_url, number=number, allowed_senders=senders)


def parse_envelopes(payload) -> List[Tuple[str, str]]:
    """(sender, text) for every dataMessage in a /v1/receive payload."""
    out: List[Tuple[str, str]] = []
    if not isinstance(payload, list):
        return out
    for item in payload:
        env = item.get("envelope", {}) if isinstance(item, dict) else {}
        text = (env.get("dataMessage") or {}).get("message")
        sender = env.get("source")
        if sender and text:
            out.append((str(sender), str(text)))
    return out


def is_allowed(cfg: GatewayConfig, sender: str) -> bool:
    """Fail closed: empty allowlist admits nobody."""
    return sender in cfg.allowed_senders


async def send(cfg: GatewayConfig, client: httpx.AsyncClient, recipient: str, text: str) -> None:
    resp = await client.post(
        f"{cfg.api_url}/v2/send",
        json={"message": text, "number": cfg.number, "recipients": [recipient]},
        timeout=30.0,
    )
    resp.raise_for_status()


async def poll_once(
    cfg: GatewayConfig,
    client: httpx.AsyncClient,
    handler: Callable[[str, str], Awaitable[str]],
) -> int:
    """One receive→filter→handle→reply pass. Returns messages handled."""
    resp = await client.get(
        f"{cfg.api_url}/v1/receive/{cfg.number}",
        params={"timeout": cfg.poll_timeout},
        timeout=float(cfg.poll_timeout) + 15.0,
    )
    resp.raise_for_status()
    handled = 0
    for sender, text in parse_envelopes(resp.json()):
        if not is_allowed(cfg, sender):
            print(f"  [!!] gateway: ignored message from non-allowlisted {sender}")
            continue
        handled += 1
        try:
            reply = await handler(text, sender)
        except Exception as exc:
            print(f"  [!!] gateway: handler failed: {exc}")
            reply = f"COOPER gateway error — the message was received but processing failed: {exc}"
        try:
            await send(cfg, client, sender, reply)
        except Exception as exc:
            print(f"  [!!] gateway: send to {sender} failed: {exc}")
    return handled


async def run_loop(
    cfg: GatewayConfig,
    handler: Callable[[str, str], Awaitable[str]],
    *,
    client: Optional[httpx.AsyncClient] = None,
    max_iterations: Optional[int] = None,
) -> None:
    """Poll forever (or max_iterations, for tests). Never raises out."""
    own_client = client is None
    client = client or httpx.AsyncClient()
    print(f"  [ok] gateway: polling {cfg.api_url} as {cfg.number} "
          f"({len(cfg.allowed_senders)} allowed sender(s))")
    iterations = 0
    try:
        while max_iterations is None or iterations < max_iterations:
            iterations += 1
            try:
                await poll_once(cfg, client, handler)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                print(f"  [!!] gateway: poll failed ({exc}) — retrying in {_ERROR_BACKOFF}s")
                await asyncio.sleep(_ERROR_BACKOFF)
    finally:
        if own_client:
            await client.aclose()

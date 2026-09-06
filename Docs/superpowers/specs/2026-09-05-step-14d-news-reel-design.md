# Step 14d (re-scoped) — News Reel

Status: **approved direction, 2026-09-05** (owner decisions inline).
Supersedes the original 14d payload (opt-out documenter), voided when that work moved to
another project. Parent spec: `Docs/superpowers/specs/2026-08-04-step-14-autonomous-jobs-design.md`.

## 1. What this is

One note, once a run, carrying the top stories in five categories — cyber, critical
infrastructure, national security, election, weather hazards — collated from many sources,
analysed, prioritised, and written where the owner reads it. The **News Reel**.

## 2. Why this restores 14d honestly

14d's original DoD had two halves: a payload (opt-out documenter) and a mechanism — *"loop
provably halts at step quota"*. The payload is void. The mechanism is not, and the News Reel
needs exactly it: iterate a fixed list of feeds, hard-capped at `quota.fetches_per_run`.

Crucially this is a **bounded iteration over a fixed list**, not the parent spec's
"bounded multi-step loop" whose tool choices are "restricted to the envelope's `steps` list".
That version reads `steps` at runtime and lets an LLM choose among them — the generic
step-executor the owner declined on 2026-09-01 (15e option (a), narrow). **The narrow-scope
invariant holds unchanged here**: nothing dispatches on `steps`, and no LLM selects a tool,
a source, or a category. The loop halts because the source list is finite and the fetch
count is capped in code.

## 3. Owner decisions (2026-09-05)

- **D1 — Weather means hazard/impact events**, not a forecast: severe weather, storms,
  floods, wildfires, quakes — weather as critical-infrastructure risk, matching the company
  it keeps in the category list.
- **D2 — US-focused, with global spillover.** US is the centre of gravity ("national
  security" and "election" both read US); major international cyber and infrastructure
  stories still surface.
- **D3 — One dated note per run**, `Obsidian Vault/00_Inbox/News-Reel-YYYY-MM-DD-<hash>.md`.
  History is kept, and a run never overwrites a reel the owner has not read.
- **D4 (mine, stated) — RSS/Atom, not SearXNG.** Search results carry no reliable
  publication date, which makes "today's top stories" guesswork; feeds give title, link and
  timestamp per item, and "the best places" then literally *is* a curated feed list. No new
  dependency: `httpx` is already present and stdlib `xml.etree` parses feeds, keeping the
  minimal-deps convention. SearXNG remains available to fill gaps later.

## 4. Sources — all live-verified 2026-09-05

Every feed below was fetched and parsed before being written down; six candidates that
returned 403/404 or unparseable bodies were dropped rather than shipped hopefully.
Stored in `Config/news_sources.yaml`, not in code, so curation is an owner edit.

| Category | Feeds |
|---|---|
| `cyber` | CISA All Advisories · Krebs on Security · BleepingComputer · The Record · Dark Reading · SecurityWeek |
| `critical_infrastructure` | CISA ICS Advisories · Utility Dive · Industrial Cyber · Nextgov · POWER Magazine |
| `national_security` | Defense One · Breaking Defense · War on the Rocks · Defense News · Just Security |
| `election` | Election Law Blog · Stateline · Verified Voting · NPR Politics |
| `weather_hazard` | NWS Severe+Extreme alerts · NHC Atlantic · NOAA SPC · USGS M4.5+ · InciWeb wildfires |

25 feeds. Two honest notes:

- **Election is the weakest category** — four feeds, of which NPR Politics is general
  politics rather than election-specific. Votebeat, Democracy Docket, Brennan Center and
  NCSL all 404'd or blocked. The analysis step filters for election relevance, and the reel
  says so when a category is thin rather than padding it.
- **The NWS feed is severity-filtered at the URL** (`severity=Severe,Extreme&status=actual`).
  Unfiltered it returns 266 active alerts, mostly minor, which would drown every other
  category; filtered it returns ~40. Verified both.

## 5. Architecture

A fourth hardcoded `job_type` branch. No new container, no new mount — `Obsidian Vault/00_Inbox`
is already bind-mounted read-write on the Open stack, and 14e's D5 directory scope already
admits a dated filename.

```
_run_news_reel
  1. load Config/news_sources.yaml            (curation is data, not code)
  2. BOUNDED LOOP over feeds, capped at quota.fetches_per_run:
        fetch (httpx, timeout) -> parse (xml.etree) -> keep items inside window_hours
        a feed that fails is SKIPPED and NAMED in the reel, never fatal
  3. dedupe by normalised URL, then by normalised title
  4. per category: ONE drafter call, untrusted item text fenced
        -> top N stories, each with a one-line "why it matters"
  5. render one note from a fixed in-code template
  6. write via _run_file_edit under the envelope's write_scope
  7. council review + evidence record
```

**Category assignment is deterministic**: an item inherits its feed's declared category. No
LLM classifies, routes, or picks sources — it only ranks and explains within a category it
was handed.

## 6. Error handling

- **A dead feed must not kill the reel.** Feeds break constantly (six did today, during
  design). Each fetch is individually guarded; failures are counted, named in the note's
  provenance section, and the run still completes. A reel that silently dropped a source
  would be the silent-empty class again (Gotchas 2026-09-05).
- **Zero items overall is a `failed` run with evidence**, not a cheerful empty note.
- **Every field off a parsed feed and off the model's JSON is type-checked** before use —
  the 2026-09-01 bug class, now at four recurrences.
- **Per-category isolation**: one category's analysis failing degrades that section to
  "analysis unavailable" and leaves the other four intact.

## 7. Security

- **Feed content is untrusted remote text**, exactly like 14c's search snippets: titles and
  summaries are attacker-influencable. All of it goes in a delimiter-neutralised data fence
  via the existing `_neutralize_delimiter`, and the injection-canary suite gains a
  `news_reel` case.
- **No new chat-reachable capability.** The RSS fetcher is job-runner-only, absent from every
  tool registry, exactly like `web_search` and `file_edit`.
- **Egress is the declared feed list only** — a fixed allowlist in config, never a URL from a
  model or from feed content. Items' own links are recorded in the note but never fetched.
- **Open workshop only**, consistent with G4: this job reaches the public internet.

## 8. Testing

- Bounded loop: more feeds than `fetches_per_run` -> exactly the cap is fetched, run halts.
- A failing feed is skipped, named, and the run still completes.
- All feeds failing -> `failed` run WITH evidence.
- Dedupe: same URL from two feeds appears once; near-identical titles collapse.
- Window: items older than `window_hours` are excluded.
- Parsing: RSS `<item>` and Atom `<entry>` both parse; malformed XML is a skipped feed.
- Type guards: model returns null/str/list -> `JobError`, never `AttributeError`.
- Injection: a feed title carrying the fence delimiter cannot close the data block.
- Category integrity: an item never appears under a category its feed did not declare.
- Live: a real run against the real feeds, with the note inspected by hand.

## 9. Out of scope

- No scheduler (no n8n workflow ships) — manual-trigger-only, like every other job.
- No full-article fetching; the reel works from feed metadata and links out.
- No paywalled or API-key sources.
- The generic step-executor / LLM tool-selection loop remains unbuilt (§2).

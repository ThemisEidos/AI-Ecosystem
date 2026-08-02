"""Shared test environment. Hermetic git identity: without it, `git clone` in
the tap-import tests derives a default committer ident by DNS-canonicalizing
the machine hostname — which hangs the whole suite on hosts where that lookup
stalls (seen 2026-08-02: hostname absent from /etc/hosts + unresponsive local
resolver). Tests must not depend on the machine's name resolution."""
import os

os.environ.setdefault("GIT_AUTHOR_NAME", "cooper-tests")
os.environ.setdefault("GIT_AUTHOR_EMAIL", "cooper-tests@localhost")
os.environ.setdefault("GIT_COMMITTER_NAME", "cooper-tests")
os.environ.setdefault("GIT_COMMITTER_EMAIL", "cooper-tests@localhost")

#!/usr/bin/env python3
"""
router.py — the pure router (the "director") for a sovereign membrane.

It RECOGNIZES and ROUTES; it never REASONS. It reads the escalations lane,
decides which TIER should answer each open row, announces the routing on the
coordination board, and gets out of the way. Because it does no thinking, it
behaves identically whether the brain behind a tier is a local 7B, a frontier
model, or a human — that model-agnostic property is the whole point:
coordination without coupling. Swap the recognizer rules for your own.

Zero dependencies: shells out to `psql`. Reads the DB connection from the
MEMBRANE_DB_URL environment variable (e.g. postgresql://user@host/db).
No credentials live in this file.

Usage:
    MEMBRANE_DB_URL=postgresql://me@localhost/mydb python3 router.py         # one pass
    MEMBRANE_DB_URL=postgresql://me@localhost/mydb python3 router.py --loop  # keep polling
"""
from __future__ import annotations
import os, sys, subprocess, time

DB_URL = os.environ.get("MEMBRANE_DB_URL")
if not DB_URL:
    sys.exit("set MEMBRANE_DB_URL  (e.g. postgresql://user@host/db)")


def q(query: str) -> str:
    """Run a query via psql; return tab-separated rows. Credentials stay in the URL."""
    r = subprocess.run(["psql", DB_URL, "-tAF", "\t", "-c", query],
                        capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        return ""
    return r.stdout.strip()


def recognize_tier(topic: str, prompt: str) -> str:
    """The ONLY 'judgment' the router makes: pattern-match a row to a tier.
    This is recognition, not reasoning. Edit these rules to fit your seats."""
    text = f"{topic} {prompt}".lower()
    if any(u in text for u in ("http://", "https://", "youtu", "x.com", "tiktok", "instagram")):
        return "residential"   # needs a residential IP / browser to fetch
    if any(k in text for k in ("recommend", "should we", "design", "why", "strategy", "decide")):
        return "frontier"      # a hard reasoning call -> bigger brain / human
    return "local"             # routine -> the cheap always-on tier


def already_routed(rid: str) -> bool:
    return bool(q(f"SELECT 1 FROM coordination WHERE ref='esc:{int(rid)}' LIMIT 1;"))


def route_once() -> int:
    rows = q("SELECT id, coalesce(topic,''), coalesce(prompt,'') "
             "FROM escalations WHERE status='needs_help' ORDER BY id;")
    if not rows:
        return 0
    routed = 0
    for line in rows.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        rid, topic, prompt = parts[0], parts[1], parts[2]
        if already_routed(rid):
            continue
        tier = recognize_tier(topic, prompt)
        note = f"recognized tier={tier}: {prompt[:60]}".replace("'", "''")
        # ANNOUNCE the route on the shared board; the tier's watcher claims it.
        # The router never writes an answer -- that is the answerer's job.
        q("INSERT INTO coordination (agent, focus, status, note, ref) "
          f"VALUES ('router','route escalation #{int(rid)}','fyi','{note}','esc:{int(rid)}');")
        print(f"#{rid} -> {tier:<11} | {topic} | {prompt[:60]}")
        routed += 1
    return routed


def main() -> None:
    loop = "--loop" in sys.argv
    while True:
        n = route_once()
        print(f"routed {n} row(s)." if n else "nothing pending.")
        if not loop:
            break
        time.sleep(10)


if __name__ == "__main__":
    main()

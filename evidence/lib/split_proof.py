#!/usr/bin/env python3
"""Splits a timestamped cluster-proof log into one run.log per claim.

usage: split_proof.py PROOF_LOG EVIDENCE_DIR STAMP_FILE
Each line of PROOF_LOG is "HH:MM:SS <line of cluster-proof.sh output>". A
section starts at a line like "HH:MM:SS cache:" and runs to the next one.
"""
import re
import sys
from pathlib import Path

log, out, stamp = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])

CLAIM = {
    "cluster": "01-cluster",
    "load balancer": "01-cluster",
    "node failure": "01-cluster",
    "broadcast": "01-cluster",
    "jobs": "03-killed-node-job",
    "job on a killed node": "03-killed-node-job",
    "events": "04-ordered-queue",
    "ordered queue": "04-ordered-queue",
    "cache": "05-cache",
    "metrics": "10-metrics",
    "database outage": "07-database-outage",
}

sections, current = [], None
for line in log.read_text().splitlines():
    m = re.match(r"^(\d\d:\d\d:\d\d) ([a-z ]+):$", line)
    if m:
        current = (m.group(2), [])
        sections.append(current)
    elif current is not None:
        current[1].append(line)
    # lines before the first section (docker noise) are not evidence

header = stamp.read_text().strip().splitlines()
by_claim = {}
for name, lines in sections:
    claim = CLAIM.get(name)
    if claim is None:
        sys.exit(f"split_proof: no claim for section {name!r} (update CLAIM)")
    first_ts = lines[0][:8] if lines else ""
    by_claim.setdefault(claim, []).append((name, lines))

for claim, secs in by_claim.items():
    path = out / claim / "run.log"
    body = ["# " + h for h in header]
    body.append("# source: example/deploy/cluster-proof.sh (3 containers + nginx + Postgres on one machine)")
    body.append("")
    for name, lines in secs:
        body.append(f"{name}:")
        body.extend(lines)
        body.append("")
    path.write_text("\n".join(body))
    print(f"{path.relative_to(out)}: {sum(len(l) for _, l in secs)} lines")

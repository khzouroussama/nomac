#!/usr/bin/env python3
"""Print the GitHub Actions matrix of corpus app ids.

Usage: matrix.py [comma-separated app ids]
With no ids (or an empty string) every app in corpus/corpus.json is selected.
Writes `matrix=<json list>` to stdout, suitable for $GITHUB_OUTPUT.
"""
import json
import sys
from pathlib import Path

manifest = json.loads((Path(__file__).resolve().parents[1] / "corpus.json").read_text())
ids = [app["id"] for app in manifest["apps"]]
requested = [s.strip() for s in (sys.argv[1] if len(sys.argv) > 1 else "").split(",") if s.strip()]
unknown = [r for r in requested if r not in ids]
if unknown:
    sys.exit(f"error: unknown corpus app ids: {', '.join(unknown)}")
print("matrix=" + json.dumps(requested or ids))

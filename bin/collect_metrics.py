#!/usr/bin/env python3
"""
Collect metrics from a 10x Genomics tool output directory.

Traverses the directory for the metric-file patterns below, dedups (a file like
metrics_summary.csv matches more than one pattern), parses each (CSV rows or
JSON), and writes a single JSON keyed by each file's path relative to the
directory.
"""
import csv
import json
import sys
from pathlib import Path

# metrics_summary.csv matches both CSV globs; the dedup in find_metric_files
# keeps it once.
METRIC_PATTERNS = ("*metrics*.csv", "*summary*.csv", "*summary*.json")


def find_metric_files(root):
    """Deduped, sorted list of metric files under root."""
    found = set()
    for pattern in METRIC_PATTERNS:
        found.update(root.rglob(pattern))
    return sorted(found)


def parse_metric_file(path):
    """Load a JSON file as-is; read a CSV as a row dict (or list of dicts)."""
    if path.suffix == ".json":
        with open(path) as f:
            return json.load(f)
    with open(path) as f:
        rows = list(csv.DictReader(f))
    return rows[0] if len(rows) == 1 else rows


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Collect 10x tool metrics")
    parser.add_argument("--tool-dir", required=True, type=Path,
                        help="Tool output directory to traverse")
    parser.add_argument("--out", required=True, type=Path,
                        help="Output JSON file path")
    args = parser.parse_args()

    metrics = {}
    for path in find_metric_files(args.tool_dir):
        rel = str(path.relative_to(args.tool_dir))
        try:
            metrics[rel] = parse_metric_file(path)
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARNING: could not parse {path}: {e}", file=sys.stderr)

    with open(args.out, "w") as f:
        json.dump(metrics, f, indent=2)


if __name__ == "__main__":
    main()

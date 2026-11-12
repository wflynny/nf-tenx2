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

METRIC_PATTERNS = ("*metrics*.csv", "*summary*.csv", "*summary*.json")
# Per-barcode tables (cellranger-arc per_barcode_metrics.csv) match the patterns
# but are not summary metrics; skip anything bigger than this. The pipeline
# passes --max-bytes from ext.max_bytes in nextflow.config.
MAX_BYTES = 5_000_000


def find_metric_files(root, max_bytes=MAX_BYTES):
    """Deduped, sorted list of metric files under root, skipping big tables."""
    found = set()
    for pattern in METRIC_PATTERNS:
        found.update(root.rglob(pattern))
    kept = []
    for p in sorted(found):
        if p.stat().st_size > max_bytes:
            print(f"WARNING: skipping {p}: larger than {max_bytes} bytes", file=sys.stderr)
        else:
            kept.append(p)
    return kept


def parse_metric_file(path):
    """Load a JSON file as-is; read a CSV as a row dict (or list of dicts)."""
    if path.suffix == ".json":
        with open(path) as f:
            return json.load(f)
    with open(path) as f:
        rows = list(csv.DictReader(f))
    return rows[0] if len(rows) == 1 else rows


def collect(root, max_bytes=MAX_BYTES):
    """Map each metric file's path relative to root to its parsed contents."""
    metrics = {}
    for path in find_metric_files(root, max_bytes):
        rel = str(path.relative_to(root))
        try:
            metrics[rel] = parse_metric_file(path)
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARNING: could not parse {path}: {e}", file=sys.stderr)
    return metrics


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Collect 10x tool metrics")
    parser.add_argument("--tool-dir", required=True, type=Path,
                        help="Tool output directory to traverse")
    parser.add_argument("--out", required=True, type=Path,
                        help="Output JSON file path")
    parser.add_argument("--max-bytes", type=int, default=MAX_BYTES,
                        help="Skip metric files larger than this")
    args = parser.parse_args()

    with open(args.out, "w") as f:
        json.dump(collect(args.tool_dir, args.max_bytes), f, indent=2)


if __name__ == "__main__":
    main()

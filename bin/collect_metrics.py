#!/usr/bin/env python3
"""
Collect metrics from a 10x Genomics tool run.

Searches two locations:
  1. The pipestance directory (*_CS/) for metrics*json files
  2. The tool output directory for metrics_summary.csv / summary.csv files

Outputs a single JSON file with all metrics keyed by their relative path.
"""
import csv
import glob
import json
import sys
from pathlib import Path


def find_pipestance_metrics(pipestance_dir):
    """Find metrics JSON files in the *_CS pipestance tree."""
    results = {}
    for pattern in glob.glob(f"{pipestance_dir}/*_CS/**/metrics*json", recursive=True):
        p = Path(pattern)
        rel = str(p.relative_to(pipestance_dir))
        try:
            with open(p) as f:
                results[rel] = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARNING: could not parse {p}: {e}", file=sys.stderr)
    return results


def find_csv_metrics(tool_dir):
    """Find metrics CSV files in the tool output directory."""
    results = {}
    tool_path = Path(tool_dir)
    for pattern_name in ("metrics_summary.csv", "summary.csv", "qc_library_metrics.csv", "qc_sample_metrics.csv"):
        for p in tool_path.rglob(pattern_name):
            rel = str(p.relative_to(tool_path))
            try:
                with open(p) as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    if len(rows) == 1:
                        results[rel] = rows[0]
                    elif len(rows) > 1:
                        results[rel] = rows
            except OSError as e:
                print(f"WARNING: could not parse {p}: {e}", file=sys.stderr)
    return results


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Collect 10x tool metrics")
    parser.add_argument("--pipestance-dir", required=True, type=Path,
                        help="Path to <dataset_id>/ directory containing *_CS/")
    parser.add_argument("--tool-dir", required=True, type=Path,
                        help="Path to renamed tool output directory (e.g. cellranger/)")
    parser.add_argument("--out", required=True, type=Path,
                        help="Output JSON file path")
    args = parser.parse_args()

    metrics = {}
    metrics.update(find_pipestance_metrics(args.pipestance_dir))
    metrics.update(find_csv_metrics(args.tool_dir))

    with open(args.out, "w") as f:
        json.dump(metrics, f, indent=2)


if __name__ == "__main__":
    main()

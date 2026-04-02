#!/usr/bin/env python3
"""
Collect and generate pipeline metadata for a sample processed with nf-tenx2.

Ingests:
  - record JSON (the pipeline input)
  - workflow JSON (nextflow runtime info)
  - input checksums (md5sum format)
  - output checksums (md5sum format)
  - metrics files (CSV, JSON)

Produces:
  - pipeline-metadata.json

No dependencies beyond Python 3 stdlib.
"""
import csv
import json
import datetime
from pathlib import Path

METADATA_SCHEMA_VERSION = "1.1.0"


def parse_checksum_file(path):
    """Parse a standard md5sum/sha256sum output file into a list of dicts."""
    checksums = []
    with open(path, "r") as fin:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                checksum, filename = parts
                # md5sum prefixes filenames with * for binary mode; strip it
                filename = filename.lstrip("*").strip()
                checksums.append({"filename": filename, "checksum": checksum})
    return sorted(checksums, key=lambda d: d["filename"])


def parse_metrics_file(path):
    """Parse a metrics file (CSV or JSON) into a dict."""
    path = Path(path)
    if not path.exists():
        return {}

    if path.suffix == ".json":
        with open(path, "r") as fin:
            mets = json.load(fin)
    elif path.suffix == ".csv":
        with open(path, "r") as fin:
            reader = csv.DictReader(fin, delimiter=",", quotechar='"')
            mets = next(reader, {})
    else:
        mets = {}

    mets["_source_file"] = path.name
    return mets


def create_metadata(args):
    metadata = {
        "metadata_generated_date": datetime.datetime.now().isoformat(),
        "metadata_schema_version": METADATA_SCHEMA_VERSION,
    }

    # Record (pipeline input JSON)
    with open(args.record, "r") as fin:
        metadata["record"] = json.load(fin)

    # Workflow info (serialized from Nextflow)
    with open(args.workflow, "r") as fin:
        metadata["workflow"] = json.load(fin)

    # Input checksums (FASTQ md5s etc.)
    metadata["input_checksums"] = []
    if args.input_checksums:
        for p in args.input_checksums:
            metadata["input_checksums"].extend(parse_checksum_file(p))

    # Output checksums (cellranger outputs)
    metadata["output_checksums"] = []
    if args.output_checksums:
        for p in args.output_checksums:
            metadata["output_checksums"].extend(parse_checksum_file(p))

    # Metrics
    metadata["metrics"] = []
    if args.metrics:
        seen = set()
        for metrics_path in args.metrics:
            mp = Path(metrics_path)
            if str(mp) in seen or not mp.exists():
                continue
            seen.add(str(mp))
            mets = parse_metrics_file(mp)
            if mets:
                metadata["metrics"].append(mets)

    # Write output
    with open(args.out, "w") as fout:
        json.dump(metadata, fout, indent=2, default=str)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Collate metadata for an individual record's processing"
    )
    parser.add_argument("--record", required=True, type=Path,
                        help="JSON file containing the pipeline input record")
    parser.add_argument("--workflow", required=True, type=Path,
                        help="JSON file containing workflow runtime info")
    parser.add_argument("--out", type=Path, default="pipeline-metadata.json",
                        help="Output metadata JSON path")
    parser.add_argument("--input-checksums", type=Path, nargs="*", default=[],
                        help="Input file checksum files (md5sum format)")
    parser.add_argument("--output-checksums", type=Path, nargs="*", default=[],
                        help="Output file checksum files (md5sum format)")
    parser.add_argument("--metrics", type=Path, nargs="*", default=[],
                        help="Metrics files (CSV or JSON)")
    args = parser.parse_args()
    create_metadata(args)


if __name__ == "__main__":
    main()

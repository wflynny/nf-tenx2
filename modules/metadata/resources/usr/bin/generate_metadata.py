#!/usr/bin/env python3
"""
Collect and generate pipeline metadata for a sample processed with nf-tenx2.

Ingests:
  - record JSON (the pipeline input)
  - workflow JSON (nextflow runtime info)
  - input checksums (md5sum format)
  - output checksums (md5sum format)
  - collected metrics JSON (from collect_metrics.py)

Produces:
  - pipeline-metadata.json

No dependencies beyond Python 3 stdlib.
"""
import json
import datetime
from pathlib import Path

METADATA_SCHEMA_VERSION = "1.2.0"


def parse_checksum_file(path):
    """Parse a standard md5sum/sha256sum output file into a list of dicts."""
    checksums = []
    # Xenium has no input checksums and passes a placeholder path that does not exist.
    if not Path(path).exists():
        return checksums
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

    # Metrics, keyed by file path relative to the tool output dir. Xenium has
    # none and passes a placeholder path that does not exist.
    metadata["metrics"] = {}
    if args.metrics and args.metrics.exists():
        with open(args.metrics, "r") as fin:
            metadata["metrics"] = json.load(fin)

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
    parser.add_argument("--metrics", type=Path, default=None,
                        help="collected_metrics.json from collect_metrics.py")
    args = parser.parse_args()
    create_metadata(args)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Convert between md5sum/sha256sum text format and JSON.

Usage:
    checksum_to_json.py input.md5 output.json   # hash text -> JSON
    checksum_to_json.py input.json output.md5    # JSON -> hash text
"""
import sys
import json
from pathlib import Path


def hash2json(hashfile, jsonfile):
    data = []
    with open(hashfile, "r") as fin:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                checksum, filename = parts
                filename = filename.lstrip("*").strip()
                data.append({"filename": filename, "checksum": checksum})

    with open(jsonfile, "w") as fout:
        json.dump(data, fout, indent=2)


def json2hash(jsonfile, hashfile):
    with open(jsonfile, "r") as fin:
        data = json.load(fin)

    with open(hashfile, "w") as fout:
        for obj in data:
            fout.write(f"{obj['checksum']}  {obj['filename']}\n")


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input> <output>", file=sys.stderr)
        print("  .md5/.sha256 input → .json output (or vice versa)", file=sys.stderr)
        sys.exit(1)

    infile = Path(sys.argv[1])
    outfile = Path(sys.argv[2])

    if infile.suffix == ".json":
        json2hash(infile, outfile)
    else:
        hash2json(infile, outfile)


if __name__ == "__main__":
    main()

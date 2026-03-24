#!/usr/bin/env python3
"""
Bidirectional converter between JSON records and cellranger CSV formats.

Supports:
  JSON → multi.csv      (sectioned CSV for cellranger multi)
  JSON → libraries.csv  (flat CSV for cellranger count)
  multi.csv → JSON
  libraries.csv → JSON

Used as a Nextflow bin/ script (available on PATH within processes).
"""
import csv
import json
import sys
from pathlib import Path
from io import StringIO
from configparser import ConfigParser


INPUT_TF_TRANSLATION = {"True": True, "False": False, "true": True, "false": False}
OUTPUT_TF_TRANSLATION = {True: "true", False: "false"}

TABULAR_SECTIONS = {"libraries", "samples"}


def _load_json(input_file):
    with open(input_file, "r") as fin:
        return json.load(fin)


def _load_csv(input_file, section_key="libraries"):
    """Load either a flat CSV or a sectioned (multi-config) CSV."""
    with open(input_file, "r") as fin:
        content = fin.read().strip()

    if not content:
        raise ValueError(f"Input file {input_file} is empty")

    # Flat CSV (no section headers)
    if content[0] != "[":
        reader = csv.DictReader(StringIO(content))
        rows = []
        for row in reader:
            row.pop("", None)  # drop trailing comma columns
            rows.append(row)
        return {section_key: rows}

    # Sectioned CSV — parse with ConfigParser
    cfg = ConfigParser(allow_no_value=True)
    cfg.optionxform = str  # preserve case

    data = {}
    cfg.read_string(content)

    for section in cfg.sections():
        lines = list(filter(None, cfg[section]))
        buffer = StringIO("\n".join(lines))

        if section in TABULAR_SECTIONS:
            reader = csv.DictReader(buffer)
            rowdata = []
            for row in reader:
                row.pop("", None)
                rowdata.append(row)
            data[section] = rowdata
        else:
            section_data = {}
            for line in lines:
                parts = line.strip().split(",", 1)
                if len(parts) == 2:
                    key, value = parts
                    value = value.strip()
                    value = INPUT_TF_TRANSLATION.get(value, value)
                    section_data[key.strip()] = value
            data[section] = section_data

    return data


class Config:
    def __init__(self, *, input_csv=None, input_json=None):
        self.input_csv = input_csv
        self.input_json = input_json
        self.config = {}

    def load_input(self, section_key="libraries"):
        if not (self.input_csv or self.input_json):
            raise ValueError("No input provided")
        if self.input_csv:
            self.config = _load_csv(self.input_csv, section_key)
        else:
            self.config = _load_json(self.input_json)

    def dump_json(self, output_file):
        output_file = Path(output_file)
        if output_file.suffix != ".json":
            raise ValueError(f"Output file [{output_file}] must be a .json file!")
        with open(output_file, "w") as fout:
            json.dump(self.config, fout, indent=2)

    def dump_multi_csv(self, output_file):
        """Write a sectioned CSV in cellranger multi format."""
        content = []
        for section_name, options in self.config.items():
            if section_name == "pipeline":
                continue

            content.append(f"[{section_name}]")
            if isinstance(options, dict):
                for option_name, option_value in options.items():
                    value = OUTPUT_TF_TRANSLATION.get(option_value, option_value)
                    content.append(f"{option_name},{value}")
            elif isinstance(options, list):
                if len(options) == 0:
                    continue
                headers = list(options[0].keys())
                content.append(",".join(headers))
                for row in options:
                    row_values = [str(row.get(h, "")) for h in headers]
                    content.append(",".join(row_values))

            content.append("")

        with open(output_file, "w") as fout:
            fout.write("\n".join(content))

    def dump_unsectioned_csv(self, output_file, section_key="libraries"):
        """Write a flat (unsectioned) CSV from a specific section."""
        if section_key not in self.config:
            raise KeyError(
                f"Section '{section_key}' not found in config. "
                f"Available sections: {list(self.config.keys())}"
            )
        rows = self.config[section_key]
        if not rows:
            raise ValueError(f"Section '{section_key}' is empty")

        with open(output_file, "w", newline="") as fout:
            headers = list(rows[0].keys())
            writer = csv.DictWriter(fout, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Convert between JSON records and cellranger CSV formats"
    )
    parser.add_argument("-i", "--input-file", required=True, type=Path)
    parser.add_argument(
        "-k", "--unsectioned-input-key", type=str, default="libraries",
        help="Section key to use when parsing a flat (unsectioned) CSV"
    )
    parser.add_argument("-o", "--output-file", required=True, type=Path)
    parser.add_argument(
        "-u", "--unsectioned-output-key", type=str, default="libraries",
        help="Section key to extract when writing a flat CSV"
    )
    parser.add_argument(
        "-t", "--output-type", required=True,
        choices=["multi", "libraries", "json"],
        help="Output format"
    )
    args = parser.parse_args()

    # Determine input type
    input_csv, input_json = None, None
    match args.input_file.suffix:
        case ".csv":
            input_csv = args.input_file
        case ".json":
            input_json = args.input_file
        case _:
            print(f"ERROR: Input file [{args.input_file}] must be .csv or .json", file=sys.stderr)
            sys.exit(1)

    config = Config(input_csv=input_csv, input_json=input_json)
    config.load_input(args.unsectioned_input_key)

    match args.output_type:
        case "multi":
            config.dump_multi_csv(args.output_file)
        case "libraries":
            config.dump_unsectioned_csv(args.output_file, args.unsectioned_output_key)
        case "json":
            config.dump_json(args.output_file)


if __name__ == "__main__":
    main()

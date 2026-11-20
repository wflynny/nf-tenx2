#!/usr/bin/env python3
"""
Check every input JSON for one pipeline before any job starts.

Values a 10x command needs are checked by building that command with
run_10x.build_command, so the required fields come from tenx_cli.json.
The checks below cover what the rules file cannot say. All problems are
printed together, and the exit code is 1 if there are any.

Usage:
    validate_records.py --pipeline gex a.json b.json ...
"""
import argparse
import json
import os
import sys
from collections import Counter

from run_10x import build_command, load_rules, version_key

PIPELINES = ("gex", "atac", "multiome", "visium", "xenium")
COUNT_TOOL = {
    "atac": "cellranger-atac-count",
    "multiome": "cellranger-arc-count",
    "visium": "spaceranger-count",
}
XENIUM_ACTIONS = ("resegment", "relabel")


def tool_for(pipeline, record):
    if pipeline == "gex":
        return "cellranger-multi" if record.get("samples") is not None else "cellranger-count"
    if pipeline == "xenium":
        return f"xeniumranger-{record['xenium']['action']}"
    return COUNT_TOOL[pipeline]


def check_record(pipeline, record, rules):
    """Problems with one record, as a list of messages. Empty means OK."""
    if not isinstance(record, dict):
        return ["not a JSON object"]
    pipe = record.get("pipeline")
    if not isinstance(pipe, dict) or not pipe.get("dataset_id") or not pipe.get("tool_version"):
        return ["needs a 'pipeline' block with dataset_id and tool_version, e.g. "
                '{"pipeline": {"dataset_id": "...", "tool_version": "9.0.1"}}']

    problems = []
    if pipeline == "xenium":
        action = (record.get("xenium") or {}).get("action")
        if action not in XENIUM_ACTIONS:
            return [f"'xenium.action' must be one of {', '.join(XENIUM_ACTIONS)}, got {action!r}"]
    else:
        libraries = record.get("libraries")
        if not isinstance(libraries, list) or not libraries:
            return ["needs a non-empty 'libraries' list"]
        # Each FASTQ dir is published as fastq/<folder name>, so the names must differ.
        dirs = list(dict.fromkeys(os.path.normpath(lib["fastqs"]) for lib in libraries if lib.get("fastqs")))
        names = [os.path.basename(d) for d in dirs]
        if len(set(names)) != len(names):
            problems.append(f"FASTQ dirs share a folder name ({', '.join(dirs)}); "
                            "each is published as fastq/<folder name>, so the names must differ")

    if pipeline == "gex" and record.get("samples") is not None:
        # The multi command line has no reference; it goes in multi.csv. Flex needs only a probe-set.
        gex = record.get("gene-expression") or {}
        if not gex.get("reference") and not gex.get("probe-set"):
            problems.append("cellranger multi needs 'gene-expression.reference' or 'gene-expression.probe-set'")
        # multi.csv has no default for it from 8.0, unlike the count command line.
        if version_key(pipe["tool_version"]) >= version_key("8.0.0") and gex.get("create-bam") is None:
            problems.append("cellranger multi 8.0+ needs 'gene-expression.create-bam' (true or false)")

    try:
        build_command(tool_for(pipeline, record), record, 1, 1, rules)
    except ValueError as e:
        problems.append(str(e))
    return problems


def check_files(pipeline, paths, rules=None):
    """Problems across all input files, each prefixed with its file name."""
    rules = rules if rules is not None else load_rules()
    problems, ids = [], Counter()
    for path in paths:
        name = os.path.basename(path)
        with open(path) as fin:
            record = json.load(fin)
        problems += [f"{name}: {p}" for p in check_record(pipeline, record, rules)]
        if isinstance(record, dict):
            ids[(record.get("pipeline") or {}).get("dataset_id")] += 1
    dupes = sorted(i for i, n in ids.items() if i and n > 1)
    if dupes:
        problems.append(f"These dataset_ids appear in more than one input JSON: {', '.join(dupes)}")
    return problems


def main():
    parser = argparse.ArgumentParser(description="Check input JSONs before a run")
    parser.add_argument("--pipeline", required=True, choices=PIPELINES)
    parser.add_argument("jsons", nargs="+")
    args = parser.parse_args()

    problems = check_files(args.pipeline, args.jsons)
    if problems:
        print("Input JSON problems:\n  " + "\n  ".join(problems), file=sys.stderr)
        sys.exit(1)
    print(f"{len(args.jsons)} input JSON(s) OK for --pipeline {args.pipeline}")


if __name__ == "__main__":
    main()

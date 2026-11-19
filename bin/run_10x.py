#!/usr/bin/env python3
"""
Build and run a 10x Genomics command from a pipeline record.

The flags for each command live in tenx_cli.json next to this script. Each
rule reads one value from the record with `from` (a dotted key such as
gene-expression.create-bam), falling back to `default`, and then:
  - kind "value":  writes `--flag <value>`, or nothing if there is no value
  - kind "switch": writes a bare `--flag` when the value equals `emit_when`,
                   or always when the rule has no `from`
A rule applies only when since <= tool version < until. A `required` rule
with no value is an error.

Besides the record, `from` can read task.cpus, task.mem, and
derived.fastq_dirs / derived.samples (joined from the libraries list).

Usage:
    run_10x.py --tool cellranger-count --cpus 16 --mem 120 < rec.json
    run_10x.py ... --dry-run     # print the command, do not run it
"""
import argparse
import json
import os
import shlex
import sys
from pathlib import Path

RULES_FILE = Path(__file__).with_name("tenx_cli.json")
RULE_KEYS = {"flag", "kind", "from", "default", "emit_when", "since", "until", "required", "note"}


def version_key(text):
    """'9.0.1' -> (9, 0, 1); '8.0' -> (8, 0, 0), so 8.0 and 8.0.0 compare equal."""
    parts = [int("".join(c for c in part if c.isdigit()) or "0") for part in str(text).split(".")]
    return tuple((parts + [0, 0, 0])[:3])


def check_rules(rules):
    """Problems in the rules file, as a list of messages. Empty means OK."""
    problems = []
    for tool, spec in rules.items():
        command = spec.get("command")
        if not command or not all(isinstance(word, str) for word in command):
            problems.append(f"{tool}: 'command' must be a non-empty list of strings")
        for rule in spec.get("args", []):
            name = f"{tool} {rule.get('flag')}"
            unknown = set(rule) - RULE_KEYS
            if unknown:
                problems.append(f"{name}: unknown keys {sorted(unknown)}")
            if not str(rule.get("flag", "")).startswith("--"):
                problems.append(f"{name}: 'flag' must start with --")
            if rule.get("kind") not in ("value", "switch"):
                problems.append(f"{name}: 'kind' must be 'value' or 'switch'")
            if rule.get("kind") == "switch" and "from" in rule and "emit_when" not in rule:
                problems.append(f"{name}: a switch with 'from' needs 'emit_when'")
            if rule.get("kind") == "value" and "from" not in rule and rule.get("default") is None:
                problems.append(f"{name}: a value rule needs 'from' or a 'default'")
            if "since" in rule and "until" in rule and version_key(rule["since"]) >= version_key(rule["until"]):
                problems.append(f"{name}: 'since' must be lower than 'until'")
    return problems


def load_rules(path=RULES_FILE):
    rules = json.loads(Path(path).read_text())
    problems = check_rules(rules)
    if problems:
        raise ValueError(f"{path}: " + "; ".join(problems))
    return rules


def lookup(data, dotted):
    """Use configobj notation in a nested dict."""
    value = data
    for key in dotted.split("."):
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value


def normalize(value):
    """String form of a value: true/false lowercased, with an inline '# ...'
    comment dropped only after true/false (paths may contain '#'). Empty
    strings count as missing."""
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    text = str(value).strip()
    flag = text.split("#")[0].strip().lower()
    if flag in ("true", "false"):
        return flag
    return text or None


def unique_joined(values):
    return ",".join(dict.fromkeys(v for v in values if v)) or None


def build_command(tool, record, cpus, mem, rules=None):
    """The argv list for `tool`, built from the record and the rules file."""
    rules = rules if rules is not None else load_rules()
    if tool not in rules:
        raise ValueError(f"unknown tool '{tool}'; known: {', '.join(rules)}")

    version_text = lookup(record, "pipeline.tool_version")
    if not version_text:
        raise ValueError("record has no pipeline.tool_version")
    version = version_key(version_text)

    libraries = record.get("libraries") or []
    data = {
        **record, 
        "task": {"cpus": cpus, "mem": mem}, 
        "derived": {
            "fastq_dirs": unique_joined(lib.get("fastqs") for lib in libraries),
            "samples": unique_joined(lib.get("fastq_id") or lib.get("sample") for lib in libraries),
        }
    }

    argv = list(rules[tool]["command"])
    for rule in rules[tool]["args"]:
        # does this rule apply to this tool?
        if "since" in rule and version < version_key(rule["since"]):
            continue
        if "until" in rule and version >= version_key(rule["until"]):
            continue
        
        value = normalize(lookup(data, rule["from"])) if "from" in rule else None
        if value is None:
            value = normalize(rule.get("default"))
        
        if rule["kind"] == "switch":
            if "from" not in rule or value == normalize(rule["emit_when"]):
                argv.append(rule["flag"])
        elif value is not None:
            argv += [rule["flag"], value]
        elif rule.get("required"):
            raise ValueError(f"{tool} {rule['flag']}: record has no value for '{rule['from']}'")

    return argv


def main():
    parser = argparse.ArgumentParser(description="Build and run a 10x Genomics command from a record")
    parser.add_argument("--tool", required=True, help="Command name in tenx_cli.json, e.g. cellranger-count")
    parser.add_argument("--cpus", required=True, type=int)
    parser.add_argument("--mem", required=True, type=int, help="Memory in GB for --localmem")
    parser.add_argument("--record", default="-", help="Record JSON file (default: stdin)")
    parser.add_argument("--dry-run", action="store_true", help="Print the command without running it")
    args = parser.parse_args()

    with (sys.stdin if args.record == "-" else open(args.record)) as fin:
        record = json.load(fin)
    try:
        argv = build_command(args.tool, record, args.cpus, args.mem)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Running: {shlex.join(argv)}", flush=True)
    if not args.dry_run:
        os.execvp(argv[0], argv)


if __name__ == "__main__":
    main()

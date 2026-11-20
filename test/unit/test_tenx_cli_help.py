#!/usr/bin/env python3
"""
Check bin/tenx_cli.json against real `--help` output of the 10x tools.

Snapshots live in test/cli-help/<rules name>@<version>.txt and are made on
the HPC with test/cli-help/capture.sh. For each snapshot, every flag whose
rule applies to that version (since <= version < until) must appear in the
help text. With no snapshots the test is skipped.

Run with: python3 -m pytest test/unit/test_tenx_cli_help.py -v
"""
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bin"))
from run_10x import load_rules, version_key  # noqa: E402

HELP_DIR = ROOT / "test" / "cli-help"
RULES = load_rules()
SNAPSHOTS = sorted(HELP_DIR.glob("*@*.txt"))


def applies(rule, version):
    v = version_key(version)
    return ("since" not in rule or v >= version_key(rule["since"])) and \
           ("until" not in rule or v < version_key(rule["until"]))


def missing_flags(tool, version, help_text):
    """Flags the rules would pass at this version that the help text lacks."""
    return [
        rule["flag"] for rule in RULES[tool]["args"]
        if applies(rule, version)
        and not re.search(rf"(?<![\w-]){re.escape(rule['flag'])}(?![\w-])", help_text)
    ]


@pytest.mark.skipif(not SNAPSHOTS, reason="no help snapshots; run test/cli-help/capture.sh on the HPC")
@pytest.mark.parametrize("snapshot", SNAPSHOTS, ids=[s.stem for s in SNAPSHOTS])
def test_rule_flags_exist_in_tool_help(snapshot):
    tool, version = snapshot.stem.split("@")
    assert tool in RULES, f"{snapshot.name}: no '{tool}' in tenx_cli.json"
    assert missing_flags(tool, version, snapshot.read_text()) == []


def test_missing_flag_is_reported():
    help_text = "Options:\n  --id <ID>\n  --transcriptome <PATH>\n  --create-bam <true|false>\n"
    missing = missing_flags("cellranger-count", "9.0.1", help_text)
    assert "--libraries" in missing
    assert "--id" not in missing and "--create-bam" not in missing
    # --no-bam stops at 8.0.0, so it is not expected in 9.0.1 help.
    assert "--no-bam" not in missing

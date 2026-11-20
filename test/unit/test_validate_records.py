#!/usr/bin/env python3
"""
Unit tests for bin/validate_records.py.

Run with: python3 -m pytest test/unit/test_validate_records.py -v
"""
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bin"))
from validate_records import check_files, check_record  # noqa: E402
from run_10x import load_rules  # noqa: E402

FIXTURES = ROOT / "test" / "input-jsons"
RULES = load_rules()


def load(name):
    return json.loads((FIXTURES / name).read_text())


@pytest.mark.parametrize("pipeline,pattern", [
    ("gex", "gex_*.json"), ("gex", "aggr/*.json"), ("atac", "atac_*.json"),
    ("multiome", "multiome_*.json"), ("visium", "visium_*.json"), ("xenium", "xenium_*.json"),
])
def test_fixtures_pass(pipeline, pattern):
    assert check_files(pipeline, sorted(FIXTURES.glob(pattern)), RULES) == []


def test_visium_without_reference_fails():
    """RecordValidator missed this; spaceranger needs --transcriptome."""
    rec = load("visium_count.json")
    del rec["gene-expression"]["reference"]
    assert any("gene-expression.reference" in p for p in check_record("visium", rec, RULES))


def test_multi_needs_reference_or_probe_set():
    rec = load("gex_multi_vdj.json")
    rec["gene-expression"].pop("probe-set", None)
    rec["gene-expression"]["reference"] = "/ref/x"
    assert check_record("gex", rec, RULES) == []
    del rec["gene-expression"]["reference"]
    assert any("probe-set" in p for p in check_record("gex", rec, RULES))


def test_multi_8_needs_create_bam():
    rec = load("gex_multi_vdj.json")
    del rec["gene-expression"]["create-bam"]
    assert any("create-bam" in p for p in check_record("gex", rec, RULES))
    rec["pipeline"]["tool_version"] = "7.2.0"
    assert check_record("gex", rec, RULES) == []


def test_samples_null_is_checked_as_count():
    """The workflow sends samples: null to cellranger count, which needs a reference."""
    rec = load("gex_count_simple.json")
    rec["samples"] = None
    rec["gene-expression"]["probe-set"] = "/ref/probes.csv"
    del rec["gene-expression"]["reference"]
    assert any("gene-expression.reference" in p for p in check_record("gex", rec, RULES))


def test_missing_pipeline_block_and_bad_xenium_action():
    rec = load("gex_count_simple.json")
    del rec["pipeline"]
    assert "pipeline" in check_record("gex", rec, RULES)[0]
    rec = load("xenium_relabel.json")
    rec["xenium"]["action"] = "relable"
    assert "xenium.action" in check_record("xenium", rec, RULES)[0]


def test_fastq_dirs_with_same_folder_name_fail():
    rec = load("gex_count_simple.json")
    rec["libraries"] = [dict(rec["libraries"][0], fastqs=d) for d in ("/a/run1", "/b/run1/")]
    assert any("folder name" in p for p in check_record("gex", rec, RULES))


def test_duplicate_ids_and_all_problems_reported(tmp_path):
    good = load("gex_count_simple.json")
    bad = load("gex_count_ab.json")
    del bad["gene-expression"]["reference"]
    for name, rec in [("a.json", good), ("b.json", good), ("c.json", bad)]:
        (tmp_path / name).write_text(json.dumps(rec))
    problems = check_files("gex", sorted(tmp_path.glob("*.json")), RULES)
    assert any(p.startswith("c.json:") for p in problems)
    assert any("appear in more than one input JSON" in p for p in problems)

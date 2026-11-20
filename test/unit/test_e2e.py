#!/usr/bin/env python3
"""
Unit tests for test/e2e/e2e.py, run against a fake software root so CI can
check the generated inputs without the 10x tools.

Run with: python3 -m pytest test/unit/test_e2e.py -v
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bin"))
sys.path.insert(0, str(ROOT / "test" / "e2e"))
import e2e  # noqa: E402
from run_10x import load_rules  # noqa: E402
from validate_records import check_files  # noqa: E402

TINY_PATHS = [
    "cellranger/{v}/external/cellranger_tiny_fastq",
    "cellranger/{v}/external/cellranger_tiny_ref",
    "cellranger-atac/{v}/external/cellranger_atac_tiny_fastq/1.0.0",
    "cellranger-atac/{v}/external/arc_testrun_files/reference",
    "cellranger-arc/{v}/external/arc_testrun_files/fastqs",
    "cellranger-arc/{v}/external/arc_testrun_files/reference",
    "spaceranger/{v}/external/spaceranger_tiny_inputs/fastqs",
    "spaceranger/{v}/external/spaceranger_tiny_ref",
]


def fake_root(tmp_path):
    for tool, versions in e2e.VERSIONS.items():
        for v in versions:
            for p in TINY_PATHS:
                if p.startswith(tool + "/"):
                    (tmp_path / p.format(v=v)).mkdir(parents=True, exist_ok=True)
            if tool == "spaceranger":
                img = tmp_path / f"spaceranger/{v}/external/spaceranger_tiny_inputs/image/tinyimage.jpg"
                img.parent.mkdir(parents=True, exist_ok=True)
                img.touch()
    return tmp_path


def test_generated_inputs_pass_validation(tmp_path):
    out = tmp_path / "inputs"
    assert e2e.write_inputs(fake_root(tmp_path / "sw"), out) > 0
    rules = load_rules()
    for folder in sorted(out.iterdir()):
        assert check_files(folder.name, sorted(folder.glob("*.json")), rules) == [], folder.name
    assert e2e.modules(out) == sorted(f"{t}/{v}" for t, vs in e2e.VERSIONS.items() for v in vs)


def test_missing_version_is_skipped(tmp_path):
    sw = fake_root(tmp_path / "sw")
    (sw / "spaceranger/3.0.0/external/spaceranger_tiny_ref").rmdir()
    e2e.write_inputs(sw, tmp_path / "inputs")
    names = [p.name for p in (tmp_path / "inputs" / "visium").glob("*.json")]
    assert names == ["visium-4-1-0.json"]


def test_check_finds_missing_and_bad_outputs(tmp_path):
    inputs = tmp_path / "inputs" / "atac"
    inputs.mkdir(parents=True)
    rec = e2e.records_for("cellranger-atac", "2.2.0", Path("/sw/cellranger-atac/2.2.0/external"))
    (rec_name, record), = rec.items()
    (inputs / rec_name).write_text(json.dumps(record))
    ds = record["pipeline"]["dataset_id"]
    root = tmp_path / "results" / "atac" / ds
    fq = root / "fastq" / "1.0.0" / "testfastq_S1_L001_R1_001.fastq.gz"
    fq.parent.mkdir(parents=True)
    fq.write_bytes(b"reads")
    (root / "pipeline-metadata.json").write_text("{}")
    (root / "cellranger-atac").mkdir()
    (root / "cellranger-atac" / "web_summary.html").touch()
    (tmp_path / "results" / "atac" / "datasets.json").write_text(json.dumps([{"dataset_id": ds}]))
    good = hashlib.md5(b"reads").hexdigest()

    (root / "hashes.md5").write_text(f"{good}  fastq/1.0.0/testfastq_S1_L001_R1_001.fastq.gz\n")
    assert e2e.check_results(tmp_path / "inputs", tmp_path / "results") == []

    (root / "hashes.md5").write_text(f"{'0' * 32}  fastq/1.0.0/testfastq_S1_L001_R1_001.fastq.gz\n")
    (root / "cellranger-atac" / "web_summary.html").unlink()
    problems = e2e.check_results(tmp_path / "inputs", tmp_path / "results")
    assert any("checksum mismatch" in p for p in problems)
    assert any("web_summary.html" in p for p in problems)

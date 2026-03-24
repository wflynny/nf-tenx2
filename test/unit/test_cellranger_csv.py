#!/usr/bin/env python3
"""
Unit tests for bin/cellranger_csv.py — the JSON ↔ CSV converter.

Run with: python3 -m pytest test/unit/test_cellranger_csv.py -v
Or:       python3 test/unit/test_cellranger_csv.py
"""
import json
import sys
import tempfile
from pathlib import Path

# Add module resources bin/ to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "modules" / "file_parsing" / "resources" / "usr" / "bin"))
from cellranger_csv import Config, _load_csv, _load_json


# ── Test fixtures ────────────────────────────────────────────────────────────

SAMPLE_COUNT_JSON = {
    "gene-expression": {
        "reference": "/ref/GRCh38",
        "create-bam": "false",
        "include-introns": "true"
    },
    "libraries": [
        {"fastqs": "/data/fastqs/gex1", "sample": "GEX_S1", "library_type": "Gene Expression"},
        {"fastqs": "/data/fastqs/ab1", "sample": "AB_S1", "library_type": "Antibody Capture"}
    ],
    "pipeline": {
        "tool_version": "9.0.1",
        "dataset_id": "Test_Count"
    }
}

SAMPLE_MULTI_JSON = {
    "gene-expression": {
        "reference": "/ref/GRCh38",
        "create-bam": "true"
    },
    "vdj": {
        "reference": "/ref/vdj-GRCh38"
    },
    "libraries": [
        {"fastqs": "/data/fastqs/gex1", "sample": "GEX_S1", "library_type": "Gene Expression"},
        {"fastqs": "/data/fastqs/vdj1", "sample": "VDJ_S1", "library_type": "VDJ-B"}
    ],
    "samples": [
        {"sample_id": "Donor1", "description": "Control"},
        {"sample_id": "Donor2", "description": "Treated"}
    ],
    "pipeline": {
        "tool_version": "9.0.1",
        "dataset_id": "Test_Multi"
    }
}

SAMPLE_MULTI_CSV = """[gene-expression]
reference,/ref/GRCh38
create-bam,true

[vdj]
reference,/ref/vdj-GRCh38

[libraries]
fastqs,sample,library_type
/data/fastqs/gex1,GEX_S1,Gene Expression
/data/fastqs/vdj1,VDJ_S1,VDJ-B

[samples]
sample_id,description
Donor1,Control
Donor2,Treated
"""

SAMPLE_FLAT_CSV = """fastqs,sample,library_type
/data/fastqs/gex1,GEX_S1,Gene Expression
/data/fastqs/ab1,AB_S1,Antibody Capture
"""


# ── Helpers ──────────────────────────────────────────────────────────────────

def write_tmp(content, suffix):
    f = tempfile.NamedTemporaryFile(mode='w', suffix=suffix, delete=False)
    f.write(content if isinstance(content, str) else json.dumps(content, indent=2))
    f.flush()
    return Path(f.name)


# ── Tests ────────────────────────────────────────────────────────────────────

def test_load_flat_csv():
    """Flat CSV should parse into a dict with the section key."""
    path = write_tmp(SAMPLE_FLAT_CSV, ".csv")
    result = _load_csv(path, section_key="libraries")
    assert "libraries" in result
    assert len(result["libraries"]) == 2
    assert result["libraries"][0]["sample"] == "GEX_S1"
    assert result["libraries"][1]["library_type"] == "Antibody Capture"


def test_load_sectioned_csv():
    """Sectioned CSV should parse all sections correctly."""
    path = write_tmp(SAMPLE_MULTI_CSV, ".csv")
    result = _load_csv(path)
    assert "gene-expression" in result
    assert result["gene-expression"]["reference"] == "/ref/GRCh38"
    assert result["gene-expression"]["create-bam"] == True  # should be converted
    assert "vdj" in result
    assert "libraries" in result
    assert len(result["libraries"]) == 2
    assert "samples" in result
    assert len(result["samples"]) == 2
    assert result["samples"][0]["sample_id"] == "Donor1"


def test_json_to_multi_csv_roundtrip():
    """JSON → multi.csv → JSON should preserve data (minus pipeline block)."""
    # Write JSON
    json_path = write_tmp(SAMPLE_MULTI_JSON, ".json")
    csv_path = Path(tempfile.mktemp(suffix=".csv"))
    rt_json_path = Path(tempfile.mktemp(suffix=".json"))

    # JSON → multi CSV
    config = Config(input_json=json_path)
    config.load_input()
    config.dump_multi_csv(csv_path)

    # multi CSV → JSON
    config2 = Config(input_csv=csv_path)
    config2.load_input()
    config2.dump_json(rt_json_path)

    roundtripped = json.loads(rt_json_path.read_text())

    # pipeline block is stripped in CSV, so compare other sections
    assert roundtripped["gene-expression"]["reference"] == "/ref/GRCh38"
    assert len(roundtripped["libraries"]) == 2
    assert len(roundtripped["samples"]) == 2
    assert roundtripped["samples"][1]["sample_id"] == "Donor2"


def test_json_to_libraries_csv_roundtrip():
    """JSON → libraries.csv → JSON should preserve libraries section."""
    json_path = write_tmp(SAMPLE_COUNT_JSON, ".json")
    csv_path = Path(tempfile.mktemp(suffix=".csv"))
    rt_json_path = Path(tempfile.mktemp(suffix=".json"))

    # JSON → flat CSV
    config = Config(input_json=json_path)
    config.load_input()
    config.dump_unsectioned_csv(csv_path, "libraries")

    # Read back
    config2 = Config(input_csv=csv_path)
    config2.load_input("libraries")

    assert len(config2.config["libraries"]) == 2
    assert config2.config["libraries"][0]["sample"] == "GEX_S1"


def test_bool_translation():
    """Boolean strings in CSV should be translated correctly."""
    csv_content = """[gene-expression]
reference,/ref/GRCh38
create-bam,True
include-introns,false
"""
    path = write_tmp(csv_content, ".csv")
    result = _load_csv(path)
    assert result["gene-expression"]["create-bam"] is True
    assert result["gene-expression"]["include-introns"] is False


def test_trailing_commas_handled():
    """Flat CSVs with trailing commas (common from Excel) should parse cleanly."""
    csv_content = "fastqs,sample,library_type,\n/data/fq,S1,Gene Expression,\n"
    path = write_tmp(csv_content, ".csv")
    result = _load_csv(path)
    assert len(result["libraries"]) == 1
    # The trailing comma column (empty key) should be stripped
    assert "" not in result["libraries"][0]


# ── Run directly ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    passed = failed = 0
    for test_fn in tests:
        try:
            test_fn()
            print(f"  ✓ {test_fn.__name__}")
            passed += 1
        except Exception as e:
            print(f"  ✗ {test_fn.__name__}: {e}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)

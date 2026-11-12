#!/usr/bin/env python3
"""
Unit tests for bin/collect_metrics.py — the 10x tool metric collector.

Run with: python3 -m pytest test/unit/test_collect_metrics.py -v
Or:       python3 test/unit/test_collect_metrics.py
"""
import sys
import tempfile
from pathlib import Path

# Add the top-level bin/ to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "bin"))
from collect_metrics import MAX_BYTES, collect, find_metric_files, parse_metric_file


# ── Test fixtures ────────────────────────────────────────────────────────────

# A typical OCM output tree. metrics_summary.csv matches both the *metrics*.csv
# and *summary*.csv globs; the decoys match none of the patterns.
OCM_OUTPUT = {
    "qc_library_metrics.csv": "Metric,Value\nReads,1000\n",
    "qc_sample_metrics.csv": "Metric,Value\nCells,500\n",
    "per_sample_outs/E103_PFlav/metrics_summary.csv": "Estimated Cells,Mean Reads\n3000,40000\n",
    "per_sample_outs/C30_PF/metrics_summary.csv": "Estimated Cells,Mean Reads\n3100,41000\n",
    "per_sample_outs/E103_PFneat/metrics_summary.csv": "Estimated Cells,Mean Reads\n3200,42000\n",
    "summary.json": '{"summary": {"n_reads": 1000}}',
    # decoys that must not be collected
    "web_summary.html": "<html></html>",
    "raw_feature_bc_matrix/barcodes.tsv.gz": "x",
    "notes.txt": "ignore me",
}

EXPECTED_METRIC_FILES = {
    "qc_library_metrics.csv",
    "qc_sample_metrics.csv",
    "per_sample_outs/E103_PFlav/metrics_summary.csv",
    "per_sample_outs/C30_PF/metrics_summary.csv",
    "per_sample_outs/E103_PFneat/metrics_summary.csv",
    "summary.json",
}


# ── Helpers ──────────────────────────────────────────────────────────────────

def build_output_tree(files):
    """Create files (rel_path -> content) under a fresh temp dir; return root."""
    root = Path(tempfile.mkdtemp())
    for rel, content in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    return root


# ── Tests ────────────────────────────────────────────────────────────────────

def test_finds_all_metric_files():
    """All three patterns are matched recursively, decoys excluded."""
    root = build_output_tree(OCM_OUTPUT)
    found = {str(p.relative_to(root)) for p in find_metric_files(root)}
    assert found == EXPECTED_METRIC_FILES


def test_metrics_summary_deduped():
    """metrics_summary.csv matches two globs but is collected only once."""
    root = build_output_tree({"per_sample_outs/s1/metrics_summary.csv": "a,b\n1,2\n"})
    assert len(find_metric_files(root)) == 1


def test_excludes_non_metric_files():
    """Files without a metric pattern (incl. web_summary.html) are skipped."""
    root = build_output_tree(OCM_OUTPUT)
    names = {p.name for p in find_metric_files(root)}
    assert "web_summary.html" not in names
    assert "barcodes.tsv.gz" not in names
    assert "notes.txt" not in names


def test_parse_csv_single_row():
    """A one-row CSV parses into a single dict."""
    root = build_output_tree({"metrics_summary.csv": "Cells,Reads\n3000,40000\n"})
    [path] = find_metric_files(root)
    assert parse_metric_file(path) == {"Cells": "3000", "Reads": "40000"}


def test_parse_csv_multi_row():
    """A multi-row CSV parses into a list of dicts."""
    root = build_output_tree({"qc_metrics.csv": "Metric,Value\nReads,1000\nCells,500\n"})
    [path] = find_metric_files(root)
    parsed = parse_metric_file(path)
    assert parsed == [{"Metric": "Reads", "Value": "1000"}, {"Metric": "Cells", "Value": "500"}]


def test_parse_json():
    """A JSON file is loaded as-is."""
    root = build_output_tree({"summary.json": '{"n_reads": 1000, "ok": true}'})
    [path] = find_metric_files(root)
    assert parse_metric_file(path) == {"n_reads": 1000, "ok": True}


def test_skips_oversized_tables():
    """A per-barcode table over MAX_BYTES matches the pattern but is skipped."""
    root = build_output_tree({"metrics_summary.csv": "a,b\n1,2\n"})
    (root / "per_barcode_metrics.csv").write_bytes(b"x" * (MAX_BYTES + 1))
    assert [p.name for p in find_metric_files(root)] == ["metrics_summary.csv"]
    assert len(find_metric_files(root, max_bytes=MAX_BYTES + 1)) == 2


def test_unparseable_file_skipped():
    """A file that fails to parse is left out; the rest are still collected."""
    root = build_output_tree({"summary.json": "not json", "metrics_summary.csv": "a,b\n1,2\n"})
    assert collect(root) == {"metrics_summary.csv": {"a": "1", "b": "2"}}


def test_collected_dict_keyed_by_relpath():
    """The collected mapping is keyed by each file's path relative to the root."""
    root = build_output_tree(OCM_OUTPUT)
    collected = collect(root)
    assert set(collected) == EXPECTED_METRIC_FILES
    assert collected["summary.json"] == {"summary": {"n_reads": 1000}}
    assert collected["per_sample_outs/C30_PF/metrics_summary.csv"] == {
        "Estimated Cells": "3100", "Mean Reads": "41000"}


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

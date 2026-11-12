#!/usr/bin/env python3
"""
Unit tests for generate_metadata.py (metadata module binary).

Run with: python3 -m pytest test/unit/test_generate_metadata.py -v
"""
import json
import sys
import tempfile
from argparse import Namespace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "modules/metadata/resources/usr/bin"))
from generate_metadata import create_metadata


def run(metrics, input_checksums="out.md5"):
    d = Path(tempfile.mkdtemp())
    (d / "rec.json").write_text('{"pipeline": {"dataset_id": "D"}}')
    (d / "wf.json").write_text("{}")
    (d / "out.md5").write_text("abc  cellranger/a\n")
    if metrics is not None:
        (d / "collected_metrics.json").write_text(json.dumps(metrics))
    create_metadata(Namespace(record=d / "rec.json", workflow=d / "wf.json", out=d / "meta.json",
                              input_checksums=[d / input_checksums], output_checksums=[d / "out.md5"],
                              metrics=d / "collected_metrics.json"))
    return json.loads((d / "meta.json").read_text())


def test_metrics_copied_as_dict():
    """The collected metrics dict is embedded as-is, keyed by file path."""
    m = {"per_sample_outs/s1/metrics_summary.csv": {"Cells": "3000"}}
    assert run(m)["metrics"] == m


def test_missing_metrics_file_gives_empty_dict():
    """Xenium passes a placeholder path that does not exist."""
    assert run(None)["metrics"] == {}


def test_missing_input_checksums_gives_empty_list():
    """Xenium passes a placeholder input-checksums path that does not exist."""
    meta = run(None, input_checksums="NO_INPUT_CHECKSUMS")
    assert meta["input_checksums"] == []
    assert meta["output_checksums"] == [{"filename": "cellranger/a", "checksum": "abc"}]


if __name__ == "__main__":
    for fn in (test_metrics_copied_as_dict, test_missing_metrics_file_gives_empty_dict,
               test_missing_input_checksums_gives_empty_list):
        fn()
        print(f"  ✓ {fn.__name__}")

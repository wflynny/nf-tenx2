#!/usr/bin/env python3
"""
Unit tests for bin/run_10x.py and its rules file bin/tenx_cli.json.

The expected commands were recorded from the Groovy CommandBuilder this script
replaced, so a mismatch means the command a tool receives has changed.

Run with: python3 -m pytest test/unit/test_run_10x.py -v
"""
import copy
import json
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bin"))
from run_10x import RULES_FILE, build_command, check_rules, load_rules  # noqa: E402

FIXTURES = ROOT / "test" / "input-jsons"

# (tool, fixture, tool_version override, {dotted key: new value}, expected command)
FIXTURE_CASES = [
    ('cellranger-count', 'gex_count_ab.json', None, {},
     'cellranger count --id TestGEX_Count-AB --transcriptome /ref/refdata-gex-GRCh38-2024-A --libraries libraries.csv --create-bam false --include-introns true --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-count', 'gex_count_ab.json', '7.2.0', {},
     'cellranger count --id TestGEX_Count-AB --transcriptome /ref/refdata-gex-GRCh38-2024-A --libraries libraries.csv --no-bam --include-introns true --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-count', 'gex_count_ab.json', '7.2.0', {'gene-expression.create-bam': 'true'},
     'cellranger count --id TestGEX_Count-AB --transcriptome /ref/refdata-gex-GRCh38-2024-A --libraries libraries.csv --include-introns true --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-count', 'gex_count_simple.json', None, {'gene-expression.create-bam': 'false #do not generate BAM'},
     'cellranger count --id TestGEX_Count-Simple --transcriptome /ref/refdata-gex-GRCh38-2024-A --libraries libraries.csv --create-bam false --include-introns true --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-multi', 'gex_multi_vdj.json', None, {},
     'cellranger multi --id TestGEX_Multi-VDJ --csv multi.csv --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-arc-count', 'multiome_count.json', None, {},
     'cellranger-arc count --id TestMultiome_Count --reference /ref/refdata-cellranger-arc-GRCh38-2024-A --libraries libraries.csv --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-arc-count', 'multiome_count.json', '2.1.0', {},
     'cellranger-arc count --id TestMultiome_Count --reference /ref/refdata-cellranger-arc-GRCh38-2024-A --libraries libraries.csv --create-bam true --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-atac-count', 'atac_count.json', None, {},
     'cellranger-atac count --id TestATAC_Count --reference /ref/refdata-cellranger-arc-GRCh38-2024-A --fastqs test/stub-fastqs/atac_sample1 --sample atac_sample1 --localcores 4 --localmem 32 --disable-ui'),
    ('spaceranger-count', 'visium_count.json', None, {},
     'spaceranger count --id TestVisium_Count --transcriptome /ref/refdata-gex-GRCh38-2024-A --fastqs test/stub-fastqs/visium_sample1 --sample visium_sample1 --create-bam true --slide V52B13-086 --area A1 --image /path/to/tissue_image.tif --localcores 4 --localmem 32 --disable-ui'),
    ('spaceranger-count', 'visium_count.json', '2.1.0', {'gene-expression.probe-set': '/ref/probes.csv'},
     'spaceranger count --id TestVisium_Count --transcriptome /ref/refdata-gex-GRCh38-2024-A --fastqs test/stub-fastqs/visium_sample1 --sample visium_sample1 --probe-set /ref/probes.csv --slide V52B13-086 --area A1 --image /path/to/tissue_image.tif --localcores 4 --localmem 32 --disable-ui'),
    ('xeniumranger-resegment', 'xenium_resegment.json', None, {},
     'xeniumranger resegment --id TestXenium_Reseg --xenium-bundle /data/xenium/output-XETG00000__slide01__20240101__120000 --localcores 4 --localmem 32'),
    ('xeniumranger-relabel', 'xenium_relabel.json', None, {},
     'xeniumranger relabel --id TestXenium_Relabel --xenium-bundle /data/xenium/output-XETG00000__slide01__20240101__120000 --panel /data/xenium/custom_panel.json --localcores 4 --localmem 32'),
]

# (tool, tool_version, reference, expected command); aggr records are built in the module.
AGGR_CASES = [
    ('cellranger-aggr', '9.0.1', None,
     'cellranger aggr --id AGG --csv aggr.csv --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-atac-aggr', '2.1.0', '/ref/atac',
     'cellranger-atac aggr --id AGG --csv aggr.csv --reference /ref/atac --localcores 4 --localmem 32 --disable-ui'),
    ('cellranger-arc-aggr', '2.1.0', '/ref/arc',
     'cellranger-arc aggr --id AGG --csv aggr.csv --reference /ref/arc --localcores 4 --localmem 32 --disable-ui'),
    ('spaceranger-aggr', '3.1.1', None,
     'spaceranger aggr --id AGG --csv aggr.csv --localcores 4 --localmem 32 --disable-ui'),
]


def record(fixture, version=None, edits=None):
    rec = json.loads((FIXTURES / fixture).read_text())
    if version:
        rec["pipeline"]["tool_version"] = version
    for dotted, value in (edits or {}).items():
        *parents, last = dotted.split(".")
        node = rec
        for key in parents:
            node = node.setdefault(key, {})
        node[last] = value
    return rec


def cmd(tool, rec):
    return shlex.join(build_command(tool, rec, 4, 32))


def test_fixture_commands_unchanged():
    for tool, fixture, version, edits, expected in FIXTURE_CASES:
        assert cmd(tool, record(fixture, version, edits)) == expected, (tool, fixture, version)


def test_aggr_commands_unchanged():
    for tool, version, reference, expected in AGGR_CASES:
        rec = {"pipeline": {"dataset_id": "AGG", "tool_version": version}}
        if reference:
            rec["reference"] = reference
        assert cmd(tool, rec) == expected, tool


def test_multiome_create_bam_read_from_multiome_block():
    """CommandBuilder read gene-expression.create-bam, which multiome records lack."""
    rec = record("multiome_count.json", "2.1.0", {"multiome.create-bam": "false"})
    assert "--create-bam false" in cmd("cellranger-arc-count", rec)


def test_version_without_patch_counts_as_dot_zero():
    """'8.0' must get the 8.0.0 flags, not the 7.x ones."""
    out = cmd("cellranger-count", record("gex_count_simple.json", "8.0"))
    assert "--create-bam false" in out and "--no-bam" not in out


def test_boolean_values_become_lowercase_strings():
    rec = record("gex_count_simple.json", None, {"gene-expression.create-bam": True})
    assert "--create-bam true" in cmd("cellranger-count", rec)


def test_hash_kept_in_paths_but_dropped_after_true_false():
    rec = record("gex_count_simple.json", "8.0.0", {
        "gene-expression.reference": "/refs/GRCh38#v2",
        "gene-expression.create-bam": "false #do not generate BAM",
    })
    out = cmd("cellranger-count", rec)
    assert "--transcriptome '/refs/GRCh38#v2'" in out
    assert "--create-bam false" in out


def test_missing_required_value_names_the_key():
    rec = record("gex_count_simple.json")
    del rec["gene-expression"]["reference"]
    try:
        build_command("cellranger-count", rec, 4, 32)
    except ValueError as e:
        assert "gene-expression.reference" in str(e)
    else:
        raise AssertionError("expected a ValueError")


def test_rules_file_is_valid():
    assert check_rules(json.loads(RULES_FILE.read_text())) == []
    load_rules()


def test_rules_check_catches_typos():
    rules = json.loads(RULES_FILE.read_text())
    bad = copy.deepcopy(rules)
    bad["cellranger-count"]["args"][3]["sinse"] = bad["cellranger-count"]["args"][3].pop("since")
    bad["cellranger-multi"]["args"][0]["kind"] = "flag"
    problems = check_rules(bad)
    assert any("sinse" in p for p in problems)
    assert any("cellranger-multi --id" in p and "kind" in p for p in problems)


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in tests:
        fn()
        print(f"  ok {fn.__name__}")

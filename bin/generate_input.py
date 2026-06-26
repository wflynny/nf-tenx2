#!/usr/bin/env python3
"""
Generate nf-tenx2 input JSON files from the cellnoor API.

Given a library ID (e.g. 26CH005-L1) or a chromium-dataset name, this resolves
the cellnoor entity graph into a complete pipeline input JSON.

Two resolution paths:

  1. Dataset path. One call to /chromium-datasets/search/detailed
     returns everything we need: the assay (pipeline and multiplexing), all
     libraries in the dataset, and each specimen with its multiplexing tag.

  2. GEMs/cDNA. If a library has no registered chromium-dataset yet (which is
     most common), the record is assembled by walking the hierarchy from the
     cDNA to its gem_well to the chromium run that produced it. The run carries
     the assay, so the pipeline and multiplexing are read directly (not guessed).
     Libraries come from the QC-passing cDNAs sharing the gem_well; specimens
     come from the cDNA. Only the dataset_id is constructed locally.

FASTQ files are located on the local filesystem with `find`; the API does not
expose FASTQ source paths.

Usage:
    generate_input.py --library 26CH005-L1 --fastq-root /gt/gt_delivery/jax
    generate_input.py --dataset 26CH040-L2_D9-D7 --fastq-root /gt/gt_delivery/jax
    generate_input.py --library 26CH005-L1 --token-file ~/.config/cellnoor/token

Requires Python 3.11+ (stdlib only).
"""
import json
import os
import re
import ssl
import subprocess
import sys
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

API_BASE = "https://api.cellnoor.jax.org"
TOKEN_DEFAULT = Path.home() / ".config" / "cellnoor" / "token"

# FASTQs are delivered here 99% of the time (override with --fastq-root).
DEFAULT_FASTQ_ROOT = "/gt/gt_delivery/jax/SingleCellBiology_Group_CT"

# A demultiplexed FASTQ filename: <prefix>_S<n>[_L<lane>]_<R|I><n>_001.fastq.gz.
# The lane token is optional; single-lane runs from bcl2fastq2 omit it. The
# captured prefix is cellranger's per-library sample id (the fastq_id).
FASTQ_RE = re.compile(r"(?P<prefix>.+)_S\d+(?:_L\d+)?_[IR]\d+_\d+\.fastq\.gz$")

CMDLINE_TO_PIPELINE = {
    "cellranger count": "gex",
    "cellranger multi": "gex",
    "cellranger-atac count": "atac",
    "cellranger-arc count": "multiome",
    "spaceranger count": "visium",
}

# Maps a cellnoor LibraryType to the cellranger feature_types string.
LIBRARY_TYPE_MAP = {
    "gene_expression": "Gene Expression",
    "chromatin_accessibility": "Chromatin Accessibility",
    "vdj": "VDJ",
    "vdj_b": "VDJ-B",
    "vdj_t": "VDJ-T",
    "vdj_t_gd": "VDJ-T-GD",
    "antibody_capture": "Antibody Capture",
    "antigen_capture": "Antigen Capture",
    "crispr_guide_capture": "CRISPR Guide Capture",
    "multiplexing_capture": "Multiplexing Capture",
    "custom": "Custom",
}

# Maps a cellnoor SampleMultiplexing to the per-sample barcode field.
MUX_BARCODE_FIELD = {
    "on_chip_multiplexing": "ocm_barcode_ids",
    "flex_barcode": "probe_barcode_ids",
    "flex_oligonucleotide_barcode": "probe_barcode_ids",
    "cellplex": "cmo_ids",
    "hashtag": "hashtag_ids",
}

# Default reference roots (override with --reference).
REF_BASE = "/sc/service/pipelines/references"
REF_PLACEHOLDER = {
    "gex": f"{REF_BASE}/10x-rna/PLACEHOLDER",
    "atac": f"{REF_BASE}/10x-atac/PLACEHOLDER",
    "multiome": f"{REF_BASE}/10x-arc/PLACEHOLDER",
    "visium": f"{REF_BASE}/10x-rna/PLACEHOLDER",
}


class CellnoorClient:
    """Minimal stdlib HTTP client for the cellnoor API (x-api-key auth)."""

    def __init__(self, token: str, base_url: str = API_BASE, verify_ssl: bool = True):
        self.token = token
        self.base_url = base_url.rstrip("/")
        self.ssl_context = None if verify_ssl else ssl._create_unverified_context()

    def _request(self, method: str, path: str, body: dict | None = None) -> Any:
        url = f"{self.base_url}{path}"
        data = json.dumps(body).encode() if body is not None else None
        headers = {"x-api-key": self.token}
        if data is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30, context=self.ssl_context) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            print(f"ERROR: API {e.code} for {method} {path}: {e.read().decode()}", file=sys.stderr)
            sys.exit(1)
        except urllib.error.URLError as e:
            print(f"ERROR: cannot reach {url}: {e.reason}", file=sys.stderr)
            sys.exit(1)

    def get(self, path: str) -> Any:
        return self._request("GET", path)

    def search(self, entity: str, filt: dict, detailed: bool = False, limit: int | None = None) -> list:
        path = f"/{entity}/search" + ("/detailed" if detailed else "")
        return self._request("POST", path, {"filter": filt, "limit": limit})

    def dataset_by_name(self, name: str) -> dict | None:
        hits = self.search("chromium-datasets", {"name": {"eq": name}}, detailed=True, limit=1)
        return hits[0] if hits else None

    def dataset_by_library(self, readable_id: str) -> dict | None:
        # A `library` predicate returns the dataset with its libraries[] trimmed
        # to just the matching library, so re-fetch the full dataset by name
        # (otherwise the other half of a multiome or 5'+VDJ dataset is dropped).
        filt = {"library": {"readable_id": {"eq": readable_id}}}
        hits = self.search("chromium-datasets", filt, limit=1)
        return self.dataset_by_name(hits[0]["name"]) if hits else None

    def library(self, readable_id: str) -> dict | None:
        hits = self.search("libraries", {"readable_id": {"eq": readable_id}}, limit=1)
        return hits[0] if hits else None

    def cdna(self, cdna_id: str) -> dict:
        return self.get(f"/cdna/{cdna_id}")

    def cdna_detailed(self, cdna_id: str) -> dict | None:
        hits = self.search("cdna/chromium", {"id": {"eq": cdna_id}}, detailed=True, limit=1)
        return hits[0] if hits else None

    def cdnas_in_gem_well(self, gem_well_id: str) -> list:
        return self.search("cdna", {"gem_well_id": {"eq": gem_well_id}})

    def libraries_for_cdna(self, cdna_id: str) -> list:
        return self.search("libraries", {"cdna_id": {"eq": cdna_id}})

    def chromium_run_for(self, specimen_readable_id: str, gem_well_id: str) -> dict | None:
        # Runs aren't filterable by gem_well_id, so find them via a specimen the
        # run shares, then pick the one whose gem_wells include this gem_well.
        runs = self.search("chromium-runs", {"specimen": {"readable_id": {"eq": specimen_readable_id}}},
                           detailed=True)
        for run in runs:
            if any(g.get("id") == gem_well_id for g in run.get("gem_wells", [])):
                return run
        return runs[0] if runs else None


# FASTQ discovery and output-id helpers

def resolve_library_fastqs(readable_id: str, fastq_root: str) -> list:
    """Find a library's FASTQs and return (fastq_id, fastqs_dir) pairs.

    Matches files named `{readable_id}_*_S<n>...fastq.gz`. For each, fastq_id is
    the name up to `_S<n>` (cellranger's per-library sample prefix) and fastqs is
    the containing directory. A library normally yields one pair; resequencing
    across runs yields several. Empty if none are found.
    """
    try:
        result = subprocess.run(
            ["find", "-L", fastq_root, "-type", "f", "-name", f"{readable_id}_*_S*.fastq.gz"],
            capture_output=True, text=True, timeout=120,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []
    pairs: dict = {}  # ordered set of (fastq_id, dir), dedups lanes and reads
    for path in result.stdout.splitlines():
        p = Path(path)
        m = FASTQ_RE.match(p.name)
        if m and p.name.startswith(f"{readable_id}_"):
            pairs[(m.group("prefix"), str(p.parent))] = None
    return list(pairs)


def sanitize_name(name: str) -> str:
    """Reduce a sample name to alphanumerics and dashes, dropping spaces,
    underscores, punctuation and super/subscripts (NFKD-folded first)."""
    folded = unicodedata.normalize("NFKD", name)
    kept = "".join(c for c in folded if c.isascii() and (c.isalnum() or c == "-"))
    return kept.strip("-")


def construct_output_id(library_ids: list, sample_names: list, max_names: int = 32) -> str:
    """Build a dataset_id as `<lib-ids>_<sanitized-sample-names>` (the lab
    convention), truncating the joined names to `max_names` chars."""
    libs = "-".join(dict.fromkeys(library_ids))
    names = [s for s in (sanitize_name(n) for n in dict.fromkeys(sample_names)) if s]
    joined = "-".join(names)[:max_names].rstrip("-")
    return f"{libs}_{joined}" if joined else libs


def specimen_names(specimens: list) -> list:
    """Distinct human sample names from a specimens list, order preserved."""
    names = [s.get("name") or s.get("readable_id") for s in specimens]
    return list(dict.fromkeys(n for n in names if n))


# Assay and pipeline interpretation

def determine_pipeline(assay: dict) -> str:
    for cmdline in assay.get("cmdlines") or []:
        if cmdline in CMDLINE_TO_PIPELINE:
            return CMDLINE_TO_PIPELINE[cmdline]
    print(f"  WARNING: unknown cmdlines {assay.get('cmdlines')}, defaulting to 'gex'", file=sys.stderr)
    return "gex"


def assay_is_multi(assay: dict) -> bool:
    """True when the dataset must run cellranger multi, which needs a samples
    block. That happens when multi is the only cmdline (5'+VDJ, feature barcode)
    or when samples are multiplexed. A singleplex assay that lists both count and
    multi runs as count.
    """
    cmdlines = assay.get("cmdlines") or []
    if cmdlines == ["cellranger multi"]:
        return True
    return assay.get("sample_multiplexing", "singleplex") != "singleplex"


def feature_type(library_type: str) -> str:
    return LIBRARY_TYPE_MAP.get(library_type, library_type)


# Record assembly

def library_entries(readable_id: str, library_type: str, fastq_root: str) -> list:
    """libraries[] entries for one library, one per fastq prefix/dir found on
    disk. Falls back to a single placeholder entry (and warns) when none are
    found, so the JSON stays hand-editable."""
    ftype = feature_type(library_type)
    pairs = resolve_library_fastqs(readable_id, fastq_root)
    if not pairs:
        print(f"  WARNING: no FASTQs found for {readable_id} under {fastq_root}, placeholder left",
              file=sys.stderr)
        return [{"fastq_id": readable_id, "fastqs": f"PLACEHOLDER/{readable_id}", "feature_types": ftype}]
    return [{"fastq_id": fid, "fastqs": d, "feature_types": ftype} for fid, d in pairs]


def build_samples(specimens: list, mux: str) -> list:
    """Build the samples[] block for a multiplexed assay from tagged specimens.

    A specimen is returned once per multiplexing barcode, so rows are grouped by
    specimen and their barcodes pipe-joined into one sample line (the cellranger
    convention, e.g. ocm_barcode_ids = "OB3|OB4"). This also keeps sample_id
    unique, which cellranger multi requires.
    """
    barcode_field = MUX_BARCODE_FIELD.get(mux)
    order: list = []
    grouped: dict = {}
    for i, spec in enumerate(specimens, 1):
        key = spec.get("readable_id") or spec.get("name") or f"sample_{i}"
        if key not in grouped:
            grouped[key] = {
                "sample_id": spec.get("name") or spec.get("readable_id") or f"sample_{i}",
                "tissue": spec.get("tissue"),
                "barcodes": [],
            }
            order.append(key)
        if barcode_field:
            # OCM barcodes are uppercased (ob1 becomes OB1); Flex and CMO tag ids
            # pass through unchanged.
            ocm = spec.get("ocm_barcode_id")
            barcode = ocm.upper() if ocm else (spec.get("multiplexing_tag") or {}).get("tag_id")
            if barcode and barcode not in grouped[key]["barcodes"]:
                grouped[key]["barcodes"].append(barcode)

    samples = []
    for key in order:
        g = grouped[key]
        sample = {"sample_id": g["sample_id"]}
        if barcode_field and g["barcodes"]:
            sample[barcode_field] = "|".join(g["barcodes"])
        sample["description"] = f"{g['tissue']} from {g['sample_id']}" if g["tissue"] else g["sample_id"]
        samples.append(sample)
    return samples


def assay_blocks(pipeline: str, reference: str | None, feature_types: set, mux: str) -> dict:
    """Build the tool-specific reference block(s) for a record."""
    ref = reference or REF_PLACEHOLDER[pipeline]
    blocks: dict = {}
    if pipeline in ("gex", "visium"):
        gex: dict = {"reference": ref}
        if mux in ("flex_barcode", "flex_oligonucleotide_barcode"):
            gex["probe-set"] = f"{REF_BASE}/probe_sets/PLACEHOLDER.csv"
        else:
            gex["include-introns"] = "true"
        gex["create-bam"] = "false"
        blocks["gene-expression"] = gex
        if feature_types & {"VDJ", "VDJ-B", "VDJ-T", "VDJ-T-GD"}:
            blocks["vdj"] = {"reference": f"{REF_BASE}/10x-vdj/PLACEHOLDER"}
    elif pipeline == "atac":
        blocks["atac"] = {"reference": ref}
    elif pipeline == "multiome":
        blocks["multiome"] = {"reference": ref}
    return blocks


def build_from_dataset(client: CellnoorClient, dataset: dict, fastq_root: str,
                       reference: str | None, tool_version: str, dataset_name: str | None) -> dict:
    """Assemble a record from a fully-detailed chromium-dataset (preferred path)."""
    assay = dataset.get("assay") or {}
    pipeline = determine_pipeline(assay)
    mux = assay.get("sample_multiplexing", "singleplex")
    print(f"  Dataset: {dataset.get('name')}")
    print(f"  Assay: {assay.get('name')} (pipeline={pipeline}, mux={mux})")

    libraries, feat_types = [], set()
    for lib in dataset.get("libraries", []):
        cdna = client.cdna(lib["cdna_id"])
        entries = library_entries(lib["readable_id"], cdna["library_type"], fastq_root)
        libraries.extend(entries)
        feat_types.update(e["feature_types"] for e in entries)
    print(f"  Libraries: {[l['fastq_id'] for l in libraries]} ({sorted(feat_types)})")

    specimens = dataset.get("specimens", [])
    record = assay_blocks(pipeline, reference, feat_types, mux)
    record["libraries"] = libraries
    if assay_is_multi(assay):
        samples = build_samples(specimens, mux)
        if samples:
            record["samples"] = samples
            print(f"  Samples: {[s['sample_id'] for s in samples]}")

    # An existing dataset already has a conventional name; use it.
    record["pipeline"] = {
        "tool_version": tool_version,
        "dataset_id": dataset_name or dataset["name"],
    }
    return record


def build_from_cdna(client: CellnoorClient, library: dict, fastq_root: str,
                    reference: str | None, tool_version: str, dataset_name: str | None,
                    pipeline_override: str | None) -> dict:
    """Build a record when a library has no registered chromium-dataset.

    Walks the GEM (cDNA, gem_well, the chromium run that produced it) to read the
    assay, so the pipeline and multiplexing are known exactly rather than guessed,
    then gathers the GEM's QC-passing libraries. Only the dataset_id is
    constructed locally.
    """
    cdna = client.cdna_detailed(library["cdna_id"])
    if cdna is None:
        print(f"ERROR: cDNA {library['cdna_id']} not found", file=sys.stderr)
        sys.exit(1)
    gem_well_id = cdna["gem_well_id"]
    specimens = cdna.get("specimens", [])

    # The chromium run that produced the gem_well carries the assay.
    spec_id = next((s["readable_id"] for s in specimens if s.get("readable_id")), None)
    run = client.chromium_run_for(spec_id, gem_well_id) if spec_id else None
    assay = (run or {}).get("assay") or {}
    pipeline = pipeline_override or determine_pipeline(assay)
    mux = assay.get("sample_multiplexing", "singleplex")
    print(f"  Library {library['readable_id']}: cDNA {cdna['readable_id']}, gem_well {gem_well_id}")
    print(f"  Assay: {assay.get('name')} (pipeline={pipeline}, mux={mux})")

    # Collect every QC-passing library across all cDNAs in the GEM. Dropping
    # libraries with additional_data.fails_quality_control handles each
    # multi-library-per-cDNA case the lab has: a QC-failed library that was
    # rebuilt (drop the failure, keep the rebuild), a multiome or 5'+VDJ cDNA
    # (different types, all pass), and a Flex-v2 cDNA split into 4 libraries (all
    # pass). The compact dataset path is already curated, so this filter is only
    # needed here.
    lib_ids, libraries, feat_types = [], [], set()
    for sib in client.cdnas_in_gem_well(gem_well_id):
        for lib in client.libraries_for_cdna(sib["id"]):
            extra = lib.get("additional_data") or {}
            if extra.get("fails_quality_control"):
                note = extra.get("failure_notes", "")
                tag = " (the requested library)" if lib["readable_id"] == library["readable_id"] else ""
                print(f"  Skipping {lib['readable_id']}: failed QC, {note}{tag}", file=sys.stderr)
                continue
            entries = library_entries(lib["readable_id"], sib["library_type"], fastq_root)
            libraries.extend(entries)
            feat_types.update(e["feature_types"] for e in entries)
            lib_ids.append(lib["readable_id"])
    if not libraries:
        print(f"ERROR: no QC-passing libraries in the GEM for {library['readable_id']}", file=sys.stderr)
        sys.exit(1)
    print(f"  Libraries in GEM: {[l['fastq_id'] for l in libraries]} ({sorted(feat_types)})")

    record = assay_blocks(pipeline, reference, feat_types, mux)
    record["libraries"] = libraries
    if assay_is_multi(assay):
        samples = build_samples(specimens, mux)
        if samples:
            record["samples"] = samples
            print(f"  Samples: {[s['sample_id'] for s in samples]}")

    dataset_id = dataset_name or construct_output_id(lib_ids, specimen_names(specimens))
    record["pipeline"] = {"tool_version": tool_version, "dataset_id": dataset_id}
    return record


# Token and CLI

def load_token(token_file: str | None) -> str:
    if token_file:
        return Path(token_file).expanduser().read_text().strip()
    if env_token := os.environ.get("CELLNOOR_TOKEN"):
        return env_token
    if TOKEN_DEFAULT.exists():
        return TOKEN_DEFAULT.read_text().strip()
    print(f"ERROR: no API token. Use --token-file, CELLNOOR_TOKEN, or {TOKEN_DEFAULT}", file=sys.stderr)
    sys.exit(1)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate nf-tenx2 input JSON from the cellnoor API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  %(prog)s --library 26CH005-L1 --fastq-root /gt/gt_delivery/jax
  %(prog)s --dataset 26CH040-L2_D9-D7 -o inputs/
  %(prog)s --library 26CH005-L1 --reference /path/to/ref --tool-version 10.0.0
""",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--library", help="Library readable_id (e.g. 26CH005-L1)")
    group.add_argument("--dataset", help="Chromium-dataset name (e.g. 26CH040-L2_D9-D7)")

    parser.add_argument("--fastq-root", default=DEFAULT_FASTQ_ROOT,
                        help=f"Root dir to search for FASTQs (default: {DEFAULT_FASTQ_ROOT})")
    parser.add_argument("--reference", default=None, help="Override reference genome path")
    parser.add_argument("--tool-version", default="10.0.0", help="10x tool version (default: 10.0.0)")
    parser.add_argument("--dataset-name", default=None, help="Override dataset_id in the output JSON")
    parser.add_argument("--pipeline", choices=["gex", "atac", "multiome", "visium"],
                        default=None, help="Override the assay's pipeline (rarely needed)")
    parser.add_argument("--token-file", default=None, help="Path to API token file")
    parser.add_argument("--no-verify-ssl", action="store_true", help="Disable SSL verification")
    parser.add_argument("-o", "--output-dir", type=Path, default=Path("."), help="Output directory")
    args = parser.parse_args()

    client = CellnoorClient(load_token(args.token_file), verify_ssl=not args.no_verify_ssl)
    print("\n  Querying cellnoor API...\n")

    if args.dataset:
        dataset = client.dataset_by_name(args.dataset)
        if dataset is None:
            print(f"ERROR: chromium-dataset '{args.dataset}' not found", file=sys.stderr)
            sys.exit(1)
        record = build_from_dataset(client, dataset, args.fastq_root, args.reference,
                                    args.tool_version, args.dataset_name)
    else:
        library = client.library(args.library)
        if library is None:
            print(f"ERROR: library '{args.library}' not found", file=sys.stderr)
            sys.exit(1)
        dataset = client.dataset_by_library(args.library)
        if dataset is not None:
            record = build_from_dataset(client, dataset, args.fastq_root, args.reference,
                                        args.tool_version, args.dataset_name)
        else:
            print(f"  No chromium-dataset for {args.library}; using cDNA fallback.")
            record = build_from_cdna(client, library, args.fastq_root, args.reference,
                                     args.tool_version, args.dataset_name, args.pipeline)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    out_file = args.output_dir / f"{record['pipeline']['dataset_id']}.json"
    out_file.write_text(json.dumps(record, indent=4) + "\n")

    print(f"\n  Written: {out_file}")
    print(f"  Pipeline: {record['pipeline']}")
    print(f"  Libraries: {len(record['libraries'])}", end="")
    print(f", Samples: {len(record['samples'])}" if "samples" in record else "")
    print()


if __name__ == "__main__":
    main()

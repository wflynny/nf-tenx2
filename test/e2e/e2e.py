#!/usr/bin/env python3
"""
End-to-end test inputs and checks, using the tiny test data that ships inside
each 10x install (<software root>/<tool>/<version>/external/...).

    e2e.py inputs --software-root ROOT --out DIR   # DIR/<pipeline>/*.json
    e2e.py check  --inputs DIR --results DIR       # after the runs finish
    e2e.py modules --inputs DIR                    # Lmod modules used, for capture.sh

test/e2e/run.sh runs both around the real pipeline runs. A version whose
tiny data is missing under ROOT is skipped with a message.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

# Versions at the tenx_cli.json rule boundaries, plus the newest we have.
VERSIONS = {
    "cellranger": ["7.2.0", "8.0.0", "10.1.0"],
    "cellranger-atac": ["2.1.0", "2.2.0"],
    "cellranger-arc": ["2.0.2", "2.2.0"],
    "spaceranger": ["3.0.0", "4.1.0"],
}
PIPELINE_OF = {"cellranger": "gex", "cellranger-atac": "atac", "cellranger-arc": "multiome", "spaceranger": "visium"}


def lib(fastqs, fastq_id, feature_types):
    return {"fastq_id": fastq_id, "fastqs": str(fastqs), "feature_types": feature_types}


def pipe(dataset_id, version, **extra):
    return {"dataset_id": dataset_id, "tool_version": version, **extra}


def records_for(tool, version, ext):
    """Input records for one tool version, as {file name: record}. ext is .../external."""
    tag = version.replace(".", "-")
    if tool == "cellranger":
        gex = {"reference": str(ext / "cellranger_tiny_ref"), "create-bam": "false"}
        libs = [lib(ext / "cellranger_tiny_fastq", "tinygex", "Gene Expression")]
        aggr_id = f"e2e-gex-aggr-{tag}"
        return {
            f"gex-count-{tag}.json": {"gene-expression": gex, "libraries": libs,
                                      "pipeline": pipe(f"e2e-gex-count-{tag}", version)},
            # samples: [] sends a singleplex record to cellranger multi.
            f"gex-multi-{tag}.json": {"gene-expression": gex, "libraries": libs, "samples": [],
                                      "pipeline": pipe(f"e2e-gex-multi-{tag}", version)},
            **{f"gex-aggr{n}-{tag}.json": {"gene-expression": gex, "libraries": libs,
                                           "pipeline": pipe(f"e2e-gex-aggr{n}-{tag}", version, aggr_id=aggr_id)}
               for n in ("A", "B")},
        }
    if tool == "cellranger-atac":
        return {f"atac-{tag}.json": {
            "atac": {"reference": str(ext / "arc_testrun_files" / "reference")},
            "libraries": [lib(ext / "cellranger_atac_tiny_fastq" / "1.0.0", "testfastq", "Chromatin Accessibility")],
            "pipeline": pipe(f"e2e-atac-{tag}", version)}}
    if tool == "cellranger-arc":
        fq = ext / "arc_testrun_files" / "fastqs"
        return {f"multiome-{tag}.json": {
            "multiome": {"reference": str(ext / "arc_testrun_files" / "reference")},
            # Both libraries share one folder; the anchored prefix match must tell them apart.
            "libraries": [lib(fq, "tiny_arc_gex", "Gene Expression"),
                          lib(fq, "tiny_arc_atac", "Chromatin Accessibility")],
            "pipeline": pipe(f"e2e-multiome-{tag}", version)}}
    if tool == "spaceranger":
        inputs = ext / "spaceranger_tiny_inputs"
        # Slide and area are what `spaceranger testrun` uses for this image.
        return {f"visium-{tag}.json": {
            "gene-expression": {"reference": str(ext / "spaceranger_tiny_ref")},
            "spatial": {"slide": "V19L29-035", "area": "A1", "image": str(inputs / "image" / "tinyimage.jpg")},
            "libraries": [lib(inputs / "fastqs", "tinytest", "Gene Expression")],
            "pipeline": pipe(f"e2e-visium-{tag}", version)}}
    raise ValueError(tool)


def missing_paths(record):
    """Input paths in a record that do not exist on disk."""
    paths = [l["fastqs"] for l in record.get("libraries", [])]
    for block in ("gene-expression", "atac", "multiome", "spatial"):
        paths += [v for k, v in (record.get(block) or {}).items() if k in ("reference", "image")]
    return [p for p in paths if not Path(p).exists()]


def write_inputs(software_root, out):
    written = 0
    for tool, versions in VERSIONS.items():
        for version in versions:
            ext = Path(software_root) / tool / version / "external"
            records = records_for(tool, version, ext)
            missing = sorted({p for r in records.values() for p in missing_paths(r)})
            if missing:
                print(f"skip {tool} {version}: missing {', '.join(missing)}", file=sys.stderr)
                continue
            folder = Path(out) / PIPELINE_OF[tool]
            folder.mkdir(parents=True, exist_ok=True)
            for name, record in records.items():
                (folder / name).write_text(json.dumps(record, indent=2) + "\n")
                written += 1
    print(f"wrote {written} input JSONs under {out}")
    return written


def bad_checksums(root):
    """Lines of <root>/hashes.md5 (md5sum format, paths relative to root) that do not match."""
    sums = root / "hashes.md5"
    if not sums.is_file():
        return []
    bad = []
    for line in sums.read_text().splitlines():
        expected, rel = line.split(maxsplit=1)
        target = root / rel.lstrip("*")
        if not target.is_file() or hashlib.md5(target.read_bytes()).hexdigest() != expected:
            bad.append(f"checksum mismatch for {rel}")
    return bad


def check_results(inputs, results):
    """Problems in the published results, as a list of messages. Empty means OK."""
    problems = []
    for folder in sorted(p for p in Path(inputs).iterdir() if p.is_dir()):
        pipeline, pub = folder.name, Path(results) / folder.name
        index = pub / "datasets.json"
        listed = index.read_text() if index.exists() else ""
        if not listed:
            problems.append(f"{pipeline}: no datasets.json")
        aggr_ids = set()
        for path in sorted(folder.glob("*.json")):
            rec = json.loads(path.read_text())
            ds = rec["pipeline"]["dataset_id"]
            aggr_ids.add(rec["pipeline"].get("aggr_id"))
            root = pub / ds
            for rel in ("pipeline-metadata.json", "hashes.md5"):
                if not (root / rel).is_file():
                    problems.append(f"{ds}: no {rel}")
            for l in rec["libraries"]:
                sub = f"fastq/{Path(l['fastqs']).name}"
                if not any((root / sub).glob(f"{l['fastq_id']}_S*.fastq.gz")):
                    problems.append(f"{ds}: no {l['fastq_id']} FASTQs in {sub}")
            problems += [f"{ds}: {p}" for p in bad_checksums(root)]
            if not any(root.rglob("web_summary.html")):
                problems.append(f"{ds}: no web_summary.html")
            if ds not in listed:
                problems.append(f"{ds}: not in {pipeline}/datasets.json")
        for aggr_id in sorted(a for a in aggr_ids if a):
            if not any((pub / aggr_id).rglob("web_summary.html")):
                problems.append(f"{aggr_id}: no aggr web_summary.html")
    return problems


def modules(inputs):
    """Lmod module names (tool/version) used by the input JSONs under inputs/<pipeline>/."""
    tool_of = {p: t for t, p in PIPELINE_OF.items()}
    return sorted({f"{tool_of[f.parent.name]}/{json.loads(f.read_text())['pipeline']['tool_version']}"
                   for f in Path(inputs).glob("*/*.json")})


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p_in = sub.add_parser("inputs", help="Write input JSONs for every tool version found")
    p_in.add_argument("--software-root", required=True, help="Folder holding <tool>/<version>/external")
    p_in.add_argument("--out", required=True)
    p_ck = sub.add_parser("check", help="Check published results against the inputs")
    p_ck.add_argument("--inputs", required=True)
    p_ck.add_argument("--results", required=True)
    p_mod = sub.add_parser("modules", help="Print the Lmod modules the inputs use")
    p_mod.add_argument("--inputs", required=True)
    args = parser.parse_args()

    if args.cmd == "modules":
        print(" ".join(modules(args.inputs)))
        return
    if args.cmd == "inputs":
        sys.exit(0 if write_inputs(args.software_root, args.out) else 1)
    problems = check_results(args.inputs, args.results)
    for p in problems:
        print(f"FAIL {p}")
    print("all results OK" if not problems else f"{len(problems)} problem(s)")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()

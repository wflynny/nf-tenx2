# nf-tenx2

A Nextflow pipeline for processing 10x Genomics single-cell and spatial data.
One pipeline, multiple entry points for different assay types.

## Supported Assays

| Pipeline    | Tool             | Assay Types |
|-------------|------------------|-------------|
| `gex`       | cellranger count | 3'/5' GEX, GEX+AB, AB-only |
| `gex`       | cellranger multi | GEX+HTO, GEX+VDJ, Flex, OCM |
| `atac`      | cellranger-atac  | scATAC-seq |
| `multiome`  | cellranger-arc   | Multiome (GEX + ATAC) |
| `visium`    | spaceranger      | Visium FF, CytAssist, HD |
| `xenium`    | xeniumranger     | Xenium resegment/relabel |

## Input

JSON files describing each dataset. The format mirrors 10x's `multi.csv`/`libraries.csv`
with an additional `pipeline` block:

```json
{
    "gene-expression": {
        "reference": "/path/to/transcriptome",
        "create-bam": "false",
        "include-introns": "true"
    },
    "libraries": [
        {"fastqs": "/path/to/fastqs", "sample": "SampleName", "library_type": "Gene Expression"}
    ],
    "pipeline": {
        "tool_version": "9.0.1",
        "dataset_id": "LibraryID_Suspension-Name"
    }
}
```

For `cellranger multi` workflows, include a `samples` section — this is the branching
trigger. See `examples/` and `test/input-jsons/` for all supported configurations.

### Creating input JSONs from existing CSVs

```bash
bin/create_input.py -i existing_multi.csv -o new_input.json --tool-version 9.0.1 --dataset-id MyDataset
```

## Invocation

```bash
# Single file
nextflow run nf-tenx2 --pipeline gex --input-json-files sample1.json

# Multiple files
nextflow run nf-tenx2 --pipeline gex --input-json-files "sample1.json sample2.json"

# Directory of JSONs
nextflow run nf-tenx2 --pipeline gex --input-dir path/to/json/files/

# With HPC profile
nextflow run nf-tenx2 -profile elion2 --pipeline gex --input-dir /path/to/jsons/
```

## Testing

Run all stub tests (no real tools needed):

```bash
bash test/run_stub_tests.sh
```

Run a specific test:

```bash
bash test/run_stub_tests.sh gex_count
```

### What stub tests validate

- Channel wiring: records flow to the correct branch (multi vs count)
- Process signatures: input/output tuples match between connected processes
- File naming: output globs resolve correctly
- Branching logic: `samples` key routes to `cellranger multi`, absence routes to `count`

## Architecture

```
main.nf                          # Entry point — routes to workflow by --pipeline
├── workflows/
│   ├── gex.nf                   # GEX: branches multi/count, runs FASTQC/MultiQC
│   ├── atac.nf                  # ATAC: cellranger-atac count
│   ├── multiome.nf              # Multiome: cellranger-arc count
│   ├── visium.nf                # Visium: spaceranger count
│   └── xenium.nf                # Xenium: resegment/relabel branching
├── modules/
│   ├── cellranger_count/        # cellranger count (env module)
│   ├── cellranger_multi/        # cellranger multi (env module)
│   ├── cellranger-atac_count/   # cellranger-atac count (env module)
│   ├── cellranger-arc_count/    # cellranger-arc count (env module)
│   ├── spaceranger_count/       # spaceranger count (env module)
│   ├── xeniumranger_resegment/  # xeniumranger resegment (env module)
│   ├── xeniumranger_relabel/    # xeniumranger relabel (env module)
│   ├── fastqc/                  # FastQC (singularity container)
│   ├── multiqc/                 # MultiQC (singularity container)
│   ├── hash/                    # MD5/SHA256 checksums
│   ├── metadata/                # Pipeline metadata JSON
│   ├── file_parsing/            # JSON ↔ CSV conversion
│   └── utils.nf                 # Helper functions
├── bin/
│   ├── cellranger_csv.py        # CSV↔JSON converter (on PATH in processes)
│   └── create_input.py          # Input file generator
└── config/
    ├── elion2.config            # Elion2 HPC profile
    ├── sumner2.config           # Sumner2 HPC profile
    └── test.config              # Local stub-test profile
```

## Tool Strategy

- **10x tools** (cellranger, spaceranger, xeniumranger): loaded via environment modules
  (`module { "cellranger/${version}" }`). Version is specified per-record in the JSON input.
- **QC tools** (FastQC, MultiQC): Singularity containers, pinned in the profile config.
- **Python scripts**: vanilla Python 3 (no extra dependencies beyond stdlib).

## Adding a New Assay

1. Create a module in `modules/newtool_action/main.nf` with `script:` and `stub:` blocks
2. Create a workflow in `workflows/newassay.nf` following the existing pattern
3. Add a `case` to `main.nf`
4. Create test JSON fixtures in `test/input-jsons/`
5. Add test entries to `test/run_stub_tests.sh`

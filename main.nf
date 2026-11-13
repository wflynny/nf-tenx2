#!/usr/bin/env nextflow

nextflow.enable.moduleBinaries = true

include { GEX        } from "./workflows/gex"
include { ATAC       } from "./workflows/atac"
include { MULTIOME   } from "./workflows/multiome"
include { VISIUM     } from "./workflows/visium"
include { XENIUM     } from "./workflows/xenium"

params {
    // Folder of input JSONs, one per dataset. Only <folder>/*.json is read, not subfolders.
    inputDir: Path
    // gex | atac | multiome | visium | xenium
    pipeline: String
}

workflow {
    main:
        // All params access is confined to this entry workflow
        def version  = workflow.manifest.version
        def pipeline = params.pipeline
        def pubdir   = workflow.outputDir.toString()

        log.info """
        ==========================================
          nf-tenx2 v${version}
          10x Genomics Processing Pipeline
        ==========================================
        Pipeline  : ${pipeline}
        Input dir : ${params.inputDir}
        Output dir: ${pubdir}
        Profile   : ${workflow.profile}
        ------------------------------------------
        """.stripIndent()

        def json_files = files("${params.inputDir}/*.json")
        if (json_files.size() == 0) {
            error "No *.json files directly inside --input-dir ${params.inputDir}"
        }
        // JsonSlurperClassic gives plain HashMaps; JsonSlurper's LazyMap throws NPEs
        // under concurrent channel access.
        def raws = json_files.collect { f ->
            try {
                return new groovy.json.JsonSlurperClassic().parseText(f.text)
            } catch (Exception e) {
                error "Could not read ${f.name} in --input-dir: ${e.message}"
            }
        }
        // Two records with the same dataset_id would publish into one folder.
        def dupes = raws.countBy { r -> r.pipeline?.dataset_id }.findAll { id, n -> id != null && n > 1 }.keySet()
        if (dupes.size() > 0) {
            error "These dataset_ids appear in more than one input JSON: ${dupes.join(', ')}"
        }
        records = channel.fromList(raws)

        // Each per-assay workflow returns a uniform set of named channels.
        // Pipelines that don't produce a given output emit channel.empty().
        def out
        if (pipeline == 'gex') {
            GEX(records, version, pubdir)
            out = GEX.out
        } else if (pipeline == 'atac') {
            ATAC(records, version, pubdir)
            out = ATAC.out
        } else if (pipeline == 'multiome') {
            MULTIOME(records, version, pubdir)
            out = MULTIOME.out
        } else if (pipeline == 'visium') {
            VISIUM(records, version, pubdir)
            out = VISIUM.out
        } else if (pipeline == 'xenium') {
            XENIUM(records, version)
            out = XENIUM.out
        } else {
            error "Unknown pipeline '${pipeline}'. Use one of: gex, atac, multiome, visium, xenium"
        }

    publish:
        results          = out.results
        metadata         = out.metadata
        input_checksums  = out.input_checksums
        fastqc           = out.fastqc
        multiqc_dataset  = out.multiqc_dataset
        multiqc_run      = out.multiqc_run
        aggr_results     = out.aggr_results
        aggr_metrics     = out.aggr_metrics
        aggr_checksums   = out.aggr_checksums

    onComplete:
        log.info "Pipeline complete. Status: ${workflow.success ? 'OK' : 'FAILED'}"
}

output {
    // Per-dataset analysis tree (cellranger / spaceranger / xeniumranger)
    results {
        path { rec, _dir -> rec.pipeline.dataset_id }
        index {
            path 'datasets.json'
        }
    }
    // Per-dataset pipeline metadata JSON
    metadata {
        path { rec, _meta -> rec.pipeline.dataset_id }
    }
    // Per-dataset FASTQ input checksums. Entries are fastq/..., so the file
    // sits at the dataset root (md5sum -c from <dataset_id>/).
    input_checksums {
        path { rec, _md5 -> rec.pipeline.dataset_id }
    }
    // Per-dataset FastQC results (one <run>_<file>_fastqc dir per FASTQ)
    fastqc {
        path { meta, _qc_dir -> "${meta.dataset_id}/fastq/qc" }
    }
    // Per-dataset MultiQC report
    multiqc_dataset {
        path { meta, _file -> "${meta.dataset_id}/fastq/qc" }
    }
    // Run-level MultiQC report
    multiqc_run {
        path 'multiqc'
    }
    // Aggregated cellranger/spaceranger results, keyed by aggr_id
    aggr_results {
        path { aggr_id, _dir -> aggr_id }
    }
    // Collected metrics per aggregation, keyed by aggr_id
    aggr_metrics {
        path { aggr_id, _json -> aggr_id }
    }
    // MD5 checksums of the aggregated output tree, keyed by aggr_id
    aggr_checksums {
        path { aggr_id, _md5 -> aggr_id }
    }
}

#!/usr/bin/env nextflow

nextflow.enable.moduleBinaries = true

include { GEX        } from "./workflows/gex"
include { ATAC       } from "./workflows/atac"
include { MULTIOME   } from "./workflows/multiome"
include { VISIUM     } from "./workflows/visium"
include { XENIUM     } from "./workflows/xenium"
include { INITIALIZE } from "./workflows/initialize"
include { collect_input_json_files } from "./modules/utils"

workflow {
    main:
        // All params access is confined to this entry workflow
        def version  = params.version
        def pipeline = params.pipeline
        def pubdir   = workflow.outputDir.toString()

        INITIALIZE(version, pipeline, params.inputJsonFiles, params.inputDir, pubdir)

        // Use JsonSlurperClassic to get thread-safe HashMaps instead of
        // LazyMap, which causes NPEs under concurrent Nextflow channel access.
        records = channel
            .fromList(collect_input_json_files(params.inputJsonFiles, params.inputDir))
            .map { json_file ->
                new groovy.json.JsonSlurperClassic().parseText(json_file.text)
            }

        // Each per-assay workflow returns a uniform set of named channels.
        // Pipelines that don't produce a given output emit channel.empty().
        def out
        if (pipeline == null) {
            error "No pipeline supplied! Use --pipeline [gex|atac|multiome|visium|xenium]"
        } else if (pipeline == 'gex') {
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
    // Per-dataset FASTQ input checksums
    input_checksums {
        path { rec, _md5 -> "${rec.pipeline.dataset_id}/fastq" }
    }
    // Per-dataset FastQC results (one dir per FASTQ)
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
}

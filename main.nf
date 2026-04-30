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
        def pubdir   = params.pubdir ?: "${workflow.launchDir}/results_${workflow.runName}"

        INITIALIZE(version, pipeline, params.inputJsonFiles, params.inputDir, pubdir)

        // Use JsonSlurperClassic to get thread-safe HashMaps instead of
        // LazyMap, which causes NPEs under concurrent Nextflow channel access.
        records = channel
            .fromList(collect_input_json_files(params.inputJsonFiles, params.inputDir))
            .map { json_file ->
                new groovy.json.JsonSlurperClassic().parseText(json_file.text)
            }

        if (pipeline == null) {
            error "No pipeline supplied! Use --pipeline [gex|atac|multiome|visium|xenium]"
        } else if (pipeline == 'gex') {
            GEX(records, version, pubdir)
        } else if (pipeline == 'atac') {
            ATAC(records, version, pubdir)
        } else if (pipeline == 'multiome') {
            MULTIOME(records, version, pubdir)
        } else if (pipeline == 'visium') {
            VISIUM(records, version, pubdir)
        } else if (pipeline == 'xenium') {
            XENIUM(records, version)
        } else {
            error "Unknown pipeline '${pipeline}'. Use one of: gex, atac, multiome, visium, xenium"
        }

    onComplete:
        log.info "Pipeline complete. Status: ${workflow.success ? 'OK' : 'FAILED'}"
}

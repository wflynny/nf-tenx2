#!/usr/bin/env nextflow

nextflow.enable.moduleBinaries = true

include { GEX        } from "./workflows/gex"
include { ATAC       } from "./workflows/atac"
include { MULTIOME   } from "./workflows/multiome"
include { VISIUM     } from "./workflows/visium"
include { XENIUM     } from "./workflows/xenium"
include { INITIALIZE } from "./workflows/initialize"
include { COMPLETE   } from "./workflows/completion"
include { collect_input_json_files } from "./modules/utils"

workflow {
    // All params access is confined to this entry workflow
    def version  = params.version
    def pipeline = params.pipeline

    INITIALIZE(version, pipeline, params.inputJsonFiles, params.inputDir, params.pubdir)

    records = channel
        .fromList(collect_input_json_files(params.inputJsonFiles, params.inputDir))
        .map { json_file ->
            new groovy.json.JsonSlurper().parseText(json_file.text)
        }

    if (pipeline == null) {
        error "No pipeline supplied! Use --pipeline [gex|atac|multiome|visium|xenium]"
    } else if (pipeline == 'gex') {
        GEX(records, version)
    } else if (pipeline == 'atac') {
        ATAC(records, version)
    } else if (pipeline == 'multiome') {
        MULTIOME(records, version)
    } else if (pipeline == 'visium') {
        VISIUM(records, version)
    } else if (pipeline == 'xenium') {
        XENIUM(records, version)
    } else {
        error "Unknown pipeline '${pipeline}'. Use one of: gex, atac, multiome, visium, xenium"
    }

    COMPLETE()
}

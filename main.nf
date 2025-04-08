#!/usr/bin/env nextflow

nextflow.enable.dsl = 2
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
    INITIALIZE(params.version)

    records = Channel.from(collect_input_json_files())
        .map { json_file ->
            def json_object = new groovy.json.JsonSlurper().parseText(json_file.text)
            return json_object
        }
        .collect()

    if (params.pipeline == null) {
        println("No pipeline supplied!")
    } else if (params.pipeline == "gex") {
        GEX(records)
    } else if (params.pipeline == "atac") {
        ATAC(records)
    } else if (params.pipeline == "multiome") {
        MULTIOME(records)
    } else if (params.pipeline == "visium") {
        VISIUM(records)
    } 

    COMPLETE()
}

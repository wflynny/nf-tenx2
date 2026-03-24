
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
    INITIALIZE(params.version)

    records = Channel
        .fromList(collect_input_json_files())
        .map { json_file ->
            new groovy.json.JsonSlurper().parseText(json_file.text)
        }

    if (params.pipeline == null) {
        error "No pipeline supplied! Use --pipeline [gex|atac|multiome|visium|xenium]"
    } else if (params.pipeline == 'gex') {
        GEX(records)
    } else if (params.pipeline == 'atac') {
        ATAC(records)
    } else if (params.pipeline == 'multiome') {
        MULTIOME(records)
    } else if (params.pipeline == 'visium') {
        VISIUM(records)
    } else if (params.pipeline == 'xenium') {
        XENIUM(records)
    } else {
        error "Unknown pipeline '${params.pipeline}'. Use one of: gex, atac, multiome, visium, xenium"
    }

    COMPLETE()
}

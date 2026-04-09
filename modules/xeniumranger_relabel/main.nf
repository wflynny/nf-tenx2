include { calc_localmem } from "../utils"

process XENIUMRANGER_RELABEL {

    label 'process_high'

    module { task.executor == 'local' ? '' : "xeniumranger/${record.pipeline.tool_version}" }

    input:
        val(record)

    output:
        tuple val(record), path("xenium-relabel"), emit: results

    script:
    def localmem  = calc_localmem(task.memory)
    def datasetId = record.pipeline.dataset_id
    def cmd       = CommandBuilder.xeniumrangerRelabel(record, task.cpus, localmem)
    """
    ${cmd}

    mkdir -p xenium-relabel
    mv ${datasetId}/outs/* xenium-relabel/
    """

    stub:
    """
    mkdir -p xenium-relabel
    touch xenium-relabel/gene_panel.json
    touch xenium-relabel/metrics_summary.csv
    """
}

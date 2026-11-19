include { calc_localmem } from "../utils"

process XENIUMRANGER_RESEGMENT {

    label 'process_high'

    module { task.executor == 'local' ? '' : "xeniumranger/${record.pipeline.tool_version}" }

    input:
        val(record)

    output:
        tuple val(record), path("xenium-reseg"), emit: results

    script:
    def localmem  = calc_localmem(task.memory)
    def datasetId = record.pipeline.dataset_id
    def rec_json = groovy.json.JsonOutput.toJson(record)
    """
    run_10x.py --tool xeniumranger-resegment --cpus ${task.cpus} --mem ${localmem} <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

    mkdir -p xenium-reseg
    mv ${datasetId}/outs/* xenium-reseg/
    """

    stub:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson(record)
    """
    run_10x.py --tool xeniumranger-resegment --cpus ${task.cpus} --mem ${localmem} --dry-run <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

    mkdir -p xenium-reseg
    touch xenium-reseg/cells.zarr.zip
    touch xenium-reseg/cell_boundaries.parquet
    touch xenium-reseg/nucleus_boundaries.parquet
    touch xenium-reseg/metrics_summary.csv
    """
}

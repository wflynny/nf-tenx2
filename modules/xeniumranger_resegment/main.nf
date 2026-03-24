process XENIUMRANGER_RESEGMENT {
    publishDir "${params.pubdir}/${record.pipeline.dataset_id}", mode: 'copy'

    label 'process_high'

    module { "xeniumranger/${record.pipeline.tool_version}" }

    input:
        val(record)

    output:
        tuple val(record), path("xenium-reseg/**"), emit: results

    script:
    def dataset_id  = record.pipeline.dataset_id
    def xenium_path = record.xenium.input_path
    """
    xeniumranger resegment \\
        --id ${dataset_id} \\
        --xenium-bundle ${xenium_path} \\
        --localcores ${task.cpus} \\
        --localmem ${Math.round(task.memory.toGiga() * 0.95)}

    mkdir -p xenium-reseg
    mv ${dataset_id}/outs/* xenium-reseg/
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    """
    mkdir -p xenium-reseg
    touch xenium-reseg/cells.zarr.zip
    touch xenium-reseg/cell_boundaries.parquet
    touch xenium-reseg/nucleus_boundaries.parquet
    touch xenium-reseg/metrics_summary.csv
    """
}

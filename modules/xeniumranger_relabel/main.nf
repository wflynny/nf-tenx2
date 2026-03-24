process XENIUMRANGER_RELABEL {

    label 'process_high'

    module "xeniumranger/${record.pipeline.tool_version}"

    input:
        val(record)

    output:
        tuple val(record), path("xenium-relabel/**"), emit: results

    script:
    def dataset_id  = record.pipeline.dataset_id
    def xenium_path = record.xenium.input_path
    def panel       = record.xenium.panel ?: ''
    """
    xeniumranger relabel \\
        --id ${dataset_id} \\
        --xenium-bundle ${xenium_path} \\
        ${panel ? "--panel ${panel}" : ''} \\
        --localcores ${task.cpus} \\
        --localmem ${Math.round(task.memory.toGiga() * 0.95)}

    mkdir -p xenium-relabel
    mv ${dataset_id}/outs/* xenium-relabel/
    """

    stub:
    """
    mkdir -p xenium-relabel
    touch xenium-relabel/gene_panel.json
    touch xenium-relabel/metrics_summary.csv
    """
}

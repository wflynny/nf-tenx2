process CELLRANGER_MULTI {
    publishDir "${params.pubdir}/${record.pipeline.dataset_id}", mode: 'copy'

    label 'process_high'

    // no long need closure here as of 25.10
    module "cellranger/${record.pipeline.tool_version}"

    input:
        tuple val(record), path("multi.csv")

    output:
        tuple val(record), path("cellranger-multi/**"),                                      emit: results
        tuple val(record), path("cellranger-multi/per_sample_outs/*/metrics_summary.csv"),   emit: metrics

    script:
    def localmem   = Math.round(task.memory.toGiga() * 0.95)
    def dataset_id = record.pipeline.dataset_id
    """
    cellranger multi \\
        --id ${dataset_id} \\
        --csv multi.csv \\
        --localcores ${task.cpus} \\
        --localmem ${localmem} \\
        --disable-ui

    mkdir -p cellranger-multi/_files
    mv multi.csv cellranger-multi/
    mv ${dataset_id}/_* cellranger-multi/_files/ || true
    mv ${dataset_id}/*.tgz cellranger-multi/ || true
    mv ${dataset_id}/outs/* cellranger-multi/
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    // Create per_sample_outs for each sample in the record
    def sample_ids = record.containsKey('samples') ? record.samples.collect { s -> s.sample_id ?: 'sample1' } : ['sample1']
    def mkdir_cmds = sample_ids.collect { sid ->
        """
        mkdir -p cellranger-multi/per_sample_outs/${sid}
        echo 'Estimated Number of Cells,Mean Reads per Cell' > cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        echo '3000,40000' >> cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        touch cellranger-multi/per_sample_outs/${sid}/web_summary.html
        """
    }.join('\n')
    """
    mkdir -p cellranger-multi/_files
    mkdir -p cellranger-multi/multi/count/raw_feature_bc_matrix
    mkdir -p cellranger-multi/multi/count/filtered_feature_bc_matrix

    cp multi.csv cellranger-multi/

    touch cellranger-multi/${dataset_id}.mri.tgz
    touch cellranger-multi/multi/count/raw_feature_bc_matrix/barcodes.tsv.gz
    touch cellranger-multi/multi/count/filtered_feature_bc_matrix/barcodes.tsv.gz

    ${mkdir_cmds}
    """
}

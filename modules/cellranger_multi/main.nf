process CELLRANGER_MULTI {
    publishDir { "${params.pubdir}/${record.pipeline.dataset_id}"}

    label 'process_high'

    module { "cellranger/${record.pipeline.tool_version}" } 

    input:
        tuple val(record), path("multi.csv")
    output:
        tuple val(record), path("cellranger-multi/*"), emit: results
        tuple val(record), 
            path("cellranger-multi/per_sample_outs/*/*summary*.json"), 
            path("cellranger-multi/per_sample_outs/*/*summary*.csv"), emit: metrics
    
    script:
    def localmem = Math.round(task.memory.toGiga() * 0.95)
    """
    outdir=${record.pipeline.dataset_id}
    cellranger multi \
        --id \${outdir} \
        --csv multi.csv \
        --localcores ${task.cpus} \
        --localmem ${localmem} \
        --disable-ui

    mkdir -p cellranger-multi/_files
    mv multi.csv cellranger-multi/
    mv \${outdir}/_* cellranger-multi/_files
    mv \${outdir}/*.tgz cellranger-multi/
    mv \${outdir}/outs/* cellranger-multi/
    """

    stub:
    """
    outdir=${record.pipeline.dataset_id}
    mkdir -p cellranger-multi/_files
    mv multi.csv cellranger-multi/
    touch cellranger-multi/\${outdir}.mri.tgz

    mkdir -p cellranger-multi/per_sample_outs/1
    touch cellranger-multi/per_sample_outs/1/metrics_summary.csv
    touch cellranger-multi/per_sample_outs/1/summary.json
    """
}
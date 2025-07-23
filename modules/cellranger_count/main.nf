process CELLRANGER_COUNT {
    publishDir { "${params.pubdir}/${record.pipeline.dataset_id}"}

    module { "cellranger/${record.pipeline.tool_version}" } 

    input:
        tuple val(record), path("libraries.csv")
    output:
        tuple val(record), path("cellranger/*"), emit: results
        tuple val(record), path("cellranger/*summary*.json"), path("cellranger/*summary*.csv"), emit: metrics
    
    script:
    def localmem = Math.round(task.memory.toGiga() * 0.95)
    """
    outdir=${record.pipeline.dataset_id}
    cellranger count \
        --id \${outdir} \
        --transcriptome ${record["gene-expression"].reference} \
        --create-bam ${record["gene-expression"]["create-bam"]} \
        --include-introns ${record["gene-expression"]["include-introns"]} \
        --libraries libraries.csv \
        --localcores ${task.cpus} \
        --localmem ${localmem} \
        --disable-ui

    mkdir -p cellranger/_files
    mv libraries.csv cellranger/
    mv \${outdir}/_* cellranger/_files
    mv \${outdir}/*.tgz cellranger/
    mv \${outdir}/outs/* cellranger/
    """

    stub:
    """
    outdir=${record.pipeline.dataset_id}
    mkdir -p cellranger/_files
    mv libraries.csv cellranger
    touch cellranger/\${outdir}.mri.gz
    touch cellranger/metrics_summary.csv
    touch cellranger/summary.json
    """
}

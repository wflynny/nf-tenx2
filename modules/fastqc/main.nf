process FASTQC {
    input:
        val(record)
    output:
        tuple val(record), path("*.html"), emit: html
        tuple val(record), path("*.zip"),  emit: zip
    script:
    def files = record.libraries.fastqs.join(" ")
    """
    fastqc --threads $task.cpus --quiet --outdir . $files
    """ 

    stub:
    def dataset_id = record.pipeline.dataset_id
    """
    touch ${dataset_id}_R1_fastqc.html
    touch ${dataset_id}_R1_fastqc.zip
    touch ${dataset_id}_R2_fastqc.html
    touch ${dataset_id}_R2_fastqc.zip
    """
}
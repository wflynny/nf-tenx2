process FASTQC {
    input:
        val(record)
    output:
        val(record)
    script:
    def files = record.libraries.fastqs.join(" ")
    """
    fastqc --threads $task.cpus --quiet --outdir . $files
    """ 

    stub:
    """
    echo ">1" > R1.fastq.gz
    echo "ACGTACGT" > R1.fastq.gz
    echo ">1" > R2.fastq.gz
    echo "ACGTACGT" > R2.fastq.gz
    touch R1.fastq.gz.html
    touch R2.fastq.gz.html
    """
}
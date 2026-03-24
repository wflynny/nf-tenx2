/*
 * Run FastQC on staged FASTQ files.
 *
 * Input: tuple of (record, list_of_fastq_directory_paths)
 * After groupTuple, the second element may be a list of paths.
 * stageAs: 'fastqs/*' handles both single and multiple directories.
 */
process FASTQC {
    label 'process_low'

    input:
        tuple val(record), path(fastq_dirs, stageAs: 'fastqs/*')

    output:
        tuple val(record), path("*.html"), emit: html
        tuple val(record), path("*.zip"),  emit: zip

    script:
    """
    FASTQS=\$(find fastqs/ -name '*.fastq.gz' -o -name '*.fq.gz' | sort)
    if [ -z "\$FASTQS" ]; then
        echo "WARNING: No FASTQ files found in staged directories" >&2
        touch no_fastqs_found.html
        touch no_fastqs_found.zip
    else
        fastqc --threads ${task.cpus} --quiet --outdir . \$FASTQS
    fi
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

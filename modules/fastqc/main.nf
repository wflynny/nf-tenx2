/*
 * Run FastQC on staged FASTQ files.
 *
 * Input: tuple of (record, list_of_fastq_directory_paths)
 * After groupTuple, the second element may be a list of paths.
 * stageAs: 'fastqs/*' handles both single and multiple directories.
 *
 * Note: The staged directories are symlinks to the original FASTQ locations
 * on the shared filesystem. Singularity autoMounts must be enabled for the
 * container to traverse these symlinks.
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
    # Search recursively — bcl2fastq output has subdirectories
    FASTQS=\$(find -L fastqs/ -type f \\( -name '*.fastq.gz' -o -name '*.fq.gz' \\) | sort)
    if [ -z "\$FASTQS" ]; then
        echo "WARNING: No FASTQ files found in staged directories" >&2
        echo "  Searched in: fastqs/" >&2
        ls -laR fastqs/ >&2 || true
        # Create placeholder outputs so downstream collect() doesn't hang
        touch no_fastqs_found.html
        touch no_fastqs_found.zip
    else
        echo "Found \$(echo "\$FASTQS" | wc -l) FASTQ files" >&2
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

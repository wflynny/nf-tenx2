/*
 * Stage sample-filtered FASTQs into a per-dataset output directory.
 *
 * Copies only the FASTQ files whose filenames start with one of the
 * sample prefixes declared in the record's libraries section.
 */
process STAGE_FASTQS {
    label 'process_low'

    input:
        tuple val(record), val(sample_prefixes), path(fastq_dirs, stageAs: 'inputs/*')

    output:
        tuple val(record), path("staged_fastqs/*.fastq.gz"), emit: fastqs

    script:
    def prefix_pattern = sample_prefixes.collect { "^${it}" }.join('|')
    """
    mkdir -p staged_fastqs
    find -L inputs/ -name '*.fastq.gz' | while read -r fq; do
        fname=\$(basename "\$fq")
        if echo "\$fname" | grep -qE '${prefix_pattern}'; then
            cp "\$fq" staged_fastqs/
        fi
    done
    """

    stub:
    """
    mkdir -p staged_fastqs
    touch staged_fastqs/stub_R1_001.fastq.gz
    touch staged_fastqs/stub_R2_001.fastq.gz
    """
}

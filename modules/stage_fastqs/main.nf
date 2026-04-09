/*
 * Stage sample-filtered FASTQs into a per-dataset fastq/ directory.
 *
 * Creates symlinks to matching FASTQs in the work directory to avoid
 * redundant copies. publishDir mode:'copy' copies the real data to
 * the final results tree: <pubdir>/<dataset_id>/fastq/
 */
process STAGE_FASTQS {
    label 'process_low'

    input:
        tuple val(record), val(sample_prefixes), path(fastq_dirs, stageAs: 'inputs/*')

    output:
        tuple val(record), path("fastq/*.fastq.gz"), emit: fastqs

    script:
    def prefix_args = sample_prefixes.collect { p -> "-e '^${p}'" }.join(' ')
    """
    mkdir -p fastq
    find -L inputs/ -name '*.fastq.gz' -print0 | while IFS= read -r -d '' fq; do
        fname=\$(basename "\$fq")
        if echo "\$fname" | grep -q ${prefix_args}; then
            ln -s "\$(readlink -f "\$fq")" "fastq/\$fname"
        fi
    done
    """

    stub:
    """
    mkdir -p fastq
    touch fastq/stub_R1_001.fastq.gz
    touch fastq/stub_R2_001.fastq.gz
    """
}

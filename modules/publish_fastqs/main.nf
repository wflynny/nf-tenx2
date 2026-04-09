/*
 * Trivial pass-through process whose sole purpose is to trigger
 * publishDir to copy sample-filtered FASTQs into the results tree.
 *
 * The filtering is done upstream in the workflow's fastq_ch channel;
 * this process just groups and publishes.
 */
process PUBLISH_FASTQS {
    label 'process_single'

    input:
        tuple val(meta), path(fastqs)

    output:
        tuple val(meta), path("*.fastq.gz"), emit: fastqs

    script:
    """
    true
    """

    stub:
    """
    true
    """
}

/*
 * Resolve and filter FASTQs for a dataset.
 *
 * The record's libraries specify parent directories that may contain
 * FASTQs from multiple datasets. This process finds only the files
 * matching this record's sample prefixes and symlinks them to the
 * output directory. publishDir mode:'copy' follows the symlinks to
 * copy real data into the results tree.
 *
 * Runs on a compute node so filesystem access is guaranteed.
 * Takes only val(record) — reads directly from the filesystem paths
 * in the record, no Nextflow path staging of input directories.
 *
 * The FASTQ filename prefix is taken from the library's `fastq_id`
 * field (multi mode) or `sample` field (count mode).
 */
process RESOLVE_FASTQS {
    label 'process_single'

    input:
        val(record)

    output:
        tuple val(record), path("fastqs/*.fastq.gz"), emit: fastqs

    script:
    def dirs = record.libraries.collect { lib -> lib.fastqs }.unique()
    def prefixes = record.libraries.collect { lib -> lib.fastq_id ?: lib.sample }.unique()
    def grep_args = prefixes.collect { p -> "-e '^${p}'" }.join(' ')
    def dir_list = dirs.collect { d -> "'${d}'" }.join(' ')
    """
    mkdir -p fastqs
    find -L ${dir_list} -name '*.fastq.gz' | while read -r fq; do
        fname=\$(basename "\$fq")
        if echo "\$fname" | grep -q ${grep_args}; then
            ln -s "\$(readlink -f "\$fq")" "fastqs/\$fname"
        fi
    done
    """

    stub:
    def prefixes = record.libraries.collect { lib -> lib.fastq_id ?: lib.sample }.unique()
    """
    mkdir -p fastqs
    ${prefixes.collect { p -> "touch fastqs/${p}_S1_L001_R1_001.fastq.gz\n    touch fastqs/${p}_S1_L001_R2_001.fastq.gz" }.join('\n    ')}
    """
}

/*
 * Resolve and filter FASTQs for a dataset.
 *
 * The record's libraries specify parent directories that may contain
 * FASTQs from multiple datasets. This process finds only the files
 * matching this record's sample prefixes and symlinks them into
 * fastq/<source dir name>/ (the sequencing core's project folder, e.g.
 * 20261109_GT26-FlynnB-338/). A top-up run adds a second folder
 * (..._GT26-FlynnB-338-run2/) whose FASTQs share file names with the first.
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
        tuple val(record), path("fastq"), emit: fastq

    script:
    def dirs = record.libraries.collect { lib -> new File(lib.fastqs.toString()).path }.unique()
    def prefixes = record.libraries.collect { lib -> lib.fastq_id ?: lib.sample }.unique()
    // Anchor on the Illumina _S<n>_ token so prefix Lib1 does not match Lib10_S2_...
    def grep_args = prefixes.collect { p -> "-e '^${p}_S[0-9][0-9]*_'" }.join(' ')
    def links = dirs.collect { d ->
        def sub = "fastq/${new File(d).name}"
        """
    mkdir -p '${sub}'
    find -L '${d}' -name '*.fastq.gz' | while read -r fq; do
        fname=\$(basename "\$fq")
        if echo "\$fname" | grep -q ${grep_args}; then
            ln -s "\$(readlink -f "\$fq")" "${sub}/\$fname"
        fi
    done"""
    }.join('\n')
    """
    mkdir -p fastq
    ${links}

    if [ -z "\$(find fastq -name '*.fastq.gz' -print -quit)" ]; then
        echo "ERROR: no FASTQs matching ${prefixes.join(', ')} under ${dirs.join(', ')}" >&2
        exit 1
    fi
    """

    stub:
    def cmds = record.libraries.collect { lib ->
        def p = lib.fastq_id ?: lib.sample
        def sub = "fastq/${new File(lib.fastqs.toString()).name}"
        "mkdir -p '${sub}' && touch '${sub}/${p}_S1_L001_R1_001.fastq.gz' '${sub}/${p}_S1_L001_R2_001.fastq.gz'"
    }.join('\n    ')
    """
    mkdir -p fastq
    ${cmds}
    """
}

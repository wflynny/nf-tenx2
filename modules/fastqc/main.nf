/*
 * Run Falco (FastQC-compatible) on individual FASTQ files.
 *
 * Falco is a C++ drop-in replacement for FastQC that is ~3x faster.
 * Its output is recognized by MultiQC's fastqc module.
 *
 * This process runs per-FASTQ-file for maximum parallelism on SLURM.
 * The workflow flatMaps records into individual files before calling this.
 */
process FASTQC {
    label 'process_single'

    input:
        tuple val(meta), path(fastq)

    output:
        tuple val(meta), path("*_fastqc.html"), emit: html
        tuple val(meta), path("*_fastqc.zip"),  emit: zip

    script:
    """
    falco --quiet --outdir . ${fastq}
    """

    stub:
    def base = fastq.baseName.replaceAll('.fastq.gz$|.fq.gz$', '')
    """
    touch ${base}_fastqc.html
    touch ${base}_fastqc.zip
    """
}

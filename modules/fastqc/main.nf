/*
 * Run Falco (FastQC-compatible) on individual FASTQ files.
 *
 * Falco is a C++ drop-in replacement for FastQC that is ~3x faster.
 * It produces fastqc_data.txt, fastqc_report.html, and summary.txt
 * which are recognized by MultiQC's fastqc module.
 *
 * Output files are placed in a per-sample subdirectory named
 * ${base}_fastqc/ to avoid collisions and match MultiQC expectations.
 */
process FASTQC {
    label 'process_single'

    input:
        tuple val(meta), path(fastq)

    output:
        tuple val(meta), path("${base}_fastqc"), emit: results

    script:
    base = fastq.baseName.replaceAll('.fastq.gz$|.fq.gz$', '')
    """
    mkdir -p ${base}_fastqc
    falco --quiet --outdir ${base}_fastqc ${fastq}
    """

    stub:
    base = fastq.baseName.replaceAll('.fastq.gz$|.fq.gz$', '')
    """
    mkdir -p ${base}_fastqc
    touch ${base}_fastqc/fastqc_data.txt
    touch ${base}_fastqc/fastqc_report.html
    touch ${base}_fastqc/summary.txt
    """
}

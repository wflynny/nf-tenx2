/*
 * Run Falco (FastQC-compatible) on individual FASTQ files.
 *
 * Falco is a C++ drop-in replacement for FastQC that is ~3x faster.
 * It produces fastqc_data.txt, fastqc_report.html, and summary.txt
 * which are recognized by MultiQC's fastqc module.
 *
 * The FASTQ is linked as <run>_<file> before running Falco, where run is
 * its source folder. Falco records that name, so MultiQC sample names stay
 * unique when a top-up run repeats the first run's file names. Output goes
 * to <run>_<file>_fastqc/.
 */
process FASTQC {
    label 'process_single'

    input:
        tuple val(meta), path(fastq)

    output:
        tuple val(meta), path("${base}_fastqc"), emit: results

    script:
    def name = "${meta.run}_${fastq.name}"
    base = name.replaceAll(/\.f(ast)?q\.gz$/, '')
    """
    ln -s ${fastq} '${name}'
    mkdir -p ${base}_fastqc
    falco --quiet --outdir ${base}_fastqc '${name}'
    """

    stub:
    base = "${meta.run}_${fastq.name}".replaceAll(/\.f(ast)?q\.gz$/, '')
    """
    mkdir -p ${base}_fastqc
    touch ${base}_fastqc/fastqc_data.txt
    touch ${base}_fastqc/fastqc_report.html
    touch ${base}_fastqc/summary.txt
    """
}

/*
 * Aggregate FastQC (and other) reports with MultiQC.
 * Collects all QC outputs for a pipeline run into a single report.
 */
process MULTIQC {
    label 'process_single'


    // Container defined in profile config

    input:
        path(qc_files, stageAs: 'multiqc_input/*')

    output:
        path("multiqc_report.html"),  emit: html
        path("multiqc_data"),         emit: data

    script:
    """
    multiqc --force --outdir . multiqc_input/
    """

    stub:
    """
    touch multiqc_report.html
    mkdir -p multiqc_data
    touch multiqc_data/multiqc_general_stats.txt
    touch multiqc_data/multiqc_data.json
    """
}

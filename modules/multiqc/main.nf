/*
 * Aggregate FastQC (and other) reports with MultiQC.
 * Collects all QC outputs for a pipeline run into a single report.
 *
 * Handles the case where no valid QC files are available
 * (e.g., FASTQC found no FASTQ files to analyze).
 */
process MULTIQC {
    label 'process_single'

    // Don't fail the pipeline if MultiQC has nothing to report
    errorStrategy 'ignore'

    input:
        path(qc_files, stageAs: 'multiqc_input/*')

    output:
        path("multiqc_report.html"),  emit: html, optional: true
        path("multiqc_data"),         emit: data, optional: true

    script:
    """
    multiqc --force --outdir . multiqc_input/ || {
        echo "WARNING: MultiQC found no results to aggregate" >&2
        exit 0
    }
    """

    stub:
    """
    touch multiqc_report.html
    mkdir -p multiqc_data
    touch multiqc_data/multiqc_general_stats.txt
    touch multiqc_data/multiqc_data.json
    """
}

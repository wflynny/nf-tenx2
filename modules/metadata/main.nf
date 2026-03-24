/*
 * Generate pipeline metadata JSON from a completed run.
 * Captures tool versions, checksums, and record info for provenance tracking.
 */
process GENERATE_METADATA {
    label 'process_single'

    publishDir "${params.pubdir}/${record.pipeline.dataset_id}", mode: 'copy'

    input:
        tuple val(record), path("checksums.*"), path(results)

    output:
        tuple val(record), path("pipeline-metadata.json"), emit: metadata

    script:
    def jsonRecord = groovy.json.JsonOutput.toJson(record)
    """
    cat <<- EOF > pipeline-metadata.json
    {
        "pipeline": {
            "name": "nf-tenx2",
            "version": "${params.version}",
            "profile": "${workflow.profile}",
            "nextflow_version": "${nextflow.version}"
        },
        "record": ${jsonRecord},
        "checksums_file": "checksums.md5"
    }
    EOF
    """

    stub:
    """
    echo '{"pipeline":{"name":"nf-tenx2","version":"stub"}}' > pipeline-metadata.json
    """
}

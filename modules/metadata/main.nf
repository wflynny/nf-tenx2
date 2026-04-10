/*
 * Metadata collection for nf-tenx2.
 *
 * CAPTURE_WORKFLOW: serializes Nextflow's workflow object to JSON (once per run)
 * HASH_INPUTS: checksums the input FASTQs for provenance
 * GENERATE_METADATA: collates record, workflow, checksums, and metrics into
 *                    a single pipeline-metadata.json per dataset
 */

process CAPTURE_WORKFLOW {
    label 'process_single'

    input:
        val(workflow_json_str)

    output:
        path("workflow.json"), emit: json

    script:
    def escaped = workflow_json_str.replace("'", "'\\''")
    """
    printf '%s\\n' '${escaped}' > workflow.json
    """

    stub:
    """
    echo '{"pipeline_name":"nf-tenx2","pipeline_version":"stub"}' > workflow.json
    """
}

process HASH_INPUTS {
    label 'process_low'

    input:
        tuple val(record), path(fastqs)

    output:
        tuple val(record), path("input_checksums.md5"), emit: hashes

    script:
    """
    shopt -s nullglob
    fqs=( *.fastq.gz *.fq.gz )
    if [ \${#fqs[@]} -gt 0 ]; then
        printf '%s\\n' "\${fqs[@]}" | sort | xargs md5sum > input_checksums.md5
    else
        echo "WARNING: no FASTQ files staged for hashing" >&2
        touch input_checksums.md5
    fi
    """

    stub:
    """
    echo "d41d8cd98f00b204e9800998ecf8427e  stub_R1.fastq.gz" > input_checksums.md5
    """
}

/*
 * Generate comprehensive pipeline metadata.
 *
 * Input channel: tuple(record, output_checksums.md5)
 *   — this is the minimum; input_checksums and metrics are optional.
 * Additional channels:
 *   - path(workflow_json)
 *   - tuple(record, input_checksums.md5)  [optional, joined by caller]
 *   - tuple(record, metrics_file)         [optional, joined by caller]
 *
 * The caller joins these before passing. If input checksums or metrics aren't
 * available (e.g. Xenium), the caller passes empty placeholder files.
 */
process GENERATE_METADATA {
    label 'process_single'

    input:
        tuple val(record), path("output_checksums.md5"), path("input_checksums.md5"), path("metrics.*")
        path(workflow_json)

    output:
        tuple val(record), path("pipeline-metadata.json"), emit: metadata

    script:
    def jsonRecord = groovy.json.JsonOutput.toJson(record)
    def metrics_files = file("metrics.*").collect { f -> f.name }.join(" ")
    """
    echo '${jsonRecord}' > rec.json

    generate_metadata.py \\
        --record rec.json \\
        --workflow ${workflow_json} \\
        --out pipeline-metadata.json \\
        --input-checksums input_checksums.md5 \\
        --output-checksums output_checksums.md5 \\
        --metrics ${metrics_files ?: ''}
    """

    stub:
    """
    echo '{"metadata_schema_version":"1.1.0","record":{},"workflow":{}}' > pipeline-metadata.json
    """
}

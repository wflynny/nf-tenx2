/*
 * File format conversion between JSON records and cellranger CSV formats.
 *
 * Design: the canonical internal format is a JSON record (parsed as a Groovy map
 * flowing through channels). These processes serialize/deserialize between that
 * representation and the CSV formats required by cellranger count/multi.
 */

/*
 * Map-based record serializers. The typed (TenxNGSRecord) counterparts used by the
 * GEX workflow live in ../file_parsing_typed; these remain here for the
 * atac/multiome/visium workflows that still pass raw Map records.
 */
process RECORD_TO_JSON_FILE {
    label 'process_single'

    input:
        val(record)

    output:
        tuple val(record), path("rec.json")

    script:
    def jsonString = groovy.json.JsonOutput.toJson(record)
    """
    cat <<- 'HEREDOC' > rec.json
    ${jsonString}
    HEREDOC
    """

    stub:
    def jsonString = groovy.json.JsonOutput.toJson(record)
    """
    cat <<- 'HEREDOC' > rec.json
    ${jsonString}
    HEREDOC
    """
}

process JSON_TO_LIBRARIES_CSV {
    label 'process_single'

    input:
        tuple val(record), path("rec.json")

    output:
        tuple val(record), path("libraries.csv")

    script:
    """
    cellranger_csv.py \\
        --input-file rec.json \\
        --output-type libraries \\
        --unsectioned-output-key libraries \\
        --output-file libraries.csv
    """

    stub:
    """
    echo "fastqs,sample,library_type" > libraries.csv
    echo "/stub/fastqs,stub_sample,Gene Expression" >> libraries.csv
    """
}

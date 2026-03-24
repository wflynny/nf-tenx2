/*
 * File format conversion between JSON records and cellranger CSV formats.
 *
 * Design: the canonical internal format is a JSON record (parsed as a Groovy map
 * flowing through channels). These processes serialize/deserialize between that
 * representation and the CSV formats required by cellranger count/multi.
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

process JSON_TO_MULTI_CSV {
    label 'process_single'

    input:
        tuple val(record), path("rec.json")

    output:
        tuple val(record), path("multi.csv")

    script:
    """
    cellranger_csv.py \\
        --input-file rec.json \\
        --output-type multi \\
        --output-file multi.csv
    """

    stub:
    """
    echo "[gene-expression]" > multi.csv
    echo "reference,/stub/ref" >> multi.csv
    echo "" >> multi.csv
    echo "[libraries]" >> multi.csv
    echo "fastq_id,fastqs,feature_types" >> multi.csv
    echo "stub,/stub/fastqs,Gene Expression" >> multi.csv
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

process LIBRARIES_CSV_TO_JSON {
    label 'process_single'

    input:
        tuple val(record), path("libraries.csv")

    output:
        tuple val(record), path("rec.json")

    script:
    """
    cellranger_csv.py \\
        --input-file libraries.csv \\
        --unsectioned-input-key libraries \\
        --output-type json \\
        --output-file rec.json
    """

    stub:
    """
    echo '{"libraries":[]}' > rec.json
    """
}

process MULTI_CSV_TO_JSON {
    label 'process_single'

    input:
        tuple val(record), path("multi.csv")

    output:
        tuple val(record), path("rec.json")

    script:
    """
    cellranger_csv.py \\
        --input-file multi.csv \\
        --output-type json \\
        --output-file rec.json
    """

    stub:
    """
    echo '{"gene-expression":{},"libraries":[]}' > rec.json
    """
}

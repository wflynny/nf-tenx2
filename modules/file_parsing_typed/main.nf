/*
 * File conversions that take a TenxNGSRecord. Separate from ../file_parsing
 * because a file with typed processes can't also hold untyped ones.
 */

nextflow.enable.types = true

include { TenxNGSRecord } from "../types"

/*
 * Write the record's original JSON (record.raw) to rec.json.
 */
process RECORD_TO_JSON_FILE_TYPED {
    label 'process_single'

    input:
        record: TenxNGSRecord

    output:
        tuple(record, file("rec.json"))

    script:
    def jsonString = groovy.json.JsonOutput.toJson(record.raw)
    """
    cat <<- 'HEREDOC' > rec.json
    ${jsonString}
    HEREDOC
    """

    stub:
    def jsonString = groovy.json.JsonOutput.toJson(record.raw)
    """
    cat <<- 'HEREDOC' > rec.json
    ${jsonString}
    HEREDOC
    """
}

/*
 * Convert a record JSON into a cellranger multi CSV (GEX multi path only).
 */
process JSON_TO_MULTI_CSV {
    label 'process_single'

    input:
        tuple(record: TenxNGSRecord, rec_json: Path)

    stage:
        stageAs rec_json, 'rec.json'

    output:
        tuple(record, file("multi.csv"))

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

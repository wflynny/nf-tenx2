/*
 * Typed (TenxRecord) file-conversion processes for the GEX workflow.
 *
 * These are the typed-port counterparts of the Map-based serializers in
 * ../file_parsing. They live in their own file because typed ports require
 * `nextflow.enable.types` per-file and a file cannot mix typed and legacy
 * processes — and ../file_parsing still hosts Map-based processes shared with
 * the atac/multiome/visium workflows.
 *
 * The record flows through as a typed TenxRecord; serialization uses
 * recordToMap() so the on-disk JSON keeps its original hyphenated keys.
 */

nextflow.enable.types = true

include { recordToMap; TenxRecord } from "../types"

/*
 * Serialize a typed TenxRecord to JSON, preserving the original hyphenated-key
 * shape via recordToMap(). The record is passed through untouched.
 */
process RECORD_TO_JSON_FILE_TYPED {
    label 'process_single'

    input:
        record: TenxRecord

    output:
        tuple(record, file("rec.json"))

    script:
    def jsonString = groovy.json.JsonOutput.toJson(recordToMap(record))
    """
    cat <<- 'HEREDOC' > rec.json
    ${jsonString}
    HEREDOC
    """

    stub:
    def jsonString = groovy.json.JsonOutput.toJson(recordToMap(record))
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
        tuple(record: TenxRecord, rec_json: Path)

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

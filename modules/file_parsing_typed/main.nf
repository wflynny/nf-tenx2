/*
 * Typed (TenxNGSRecord) file-conversion processes for the NGS workflows.
 *
 * RECORD_TO_JSON_FILE_TYPED is used by all four NGS assays (GEX, ATAC,
 * Multiome, Visium); JSON_TO_MULTI_CSV is GEX-multi only. They live in their
 * own file because typed ports require `nextflow.enable.types` per-file and a
 * file cannot mix typed and legacy processes — and ../file_parsing still hosts
 * Map-based processes (JSON_TO_LIBRARIES_CSV etc.) shared with the legacy/raw
 * code paths.
 *
 * The record flows through as a typed TenxNGSRecord; serialization uses
 * recordToMap() so the on-disk JSON keeps its original hyphenated keys.
 */

nextflow.enable.types = true

include { recordToMap; TenxNGSRecord } from "../types"

/*
 * Serialize a typed TenxNGSRecord to JSON, preserving the original hyphenated-key
 * shape via recordToMap(). The record is passed through untouched.
 */
process RECORD_TO_JSON_FILE_TYPED {
    label 'process_single'

    input:
        record: TenxNGSRecord

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

/**
 * Input record validation for nf-tenx2.
 *
 * Placed in lib/ so it's available on the classpath to all .nf files
 * without needing include {} statements. Call as:
 *
 *   RecordValidator.validateGex(record)
 *   RecordValidator.validateAtac(record)
 *
 * Throws descriptive errors on invalid records, preventing cryptic
 * failures deep in the pipeline.
 */
class RecordValidator {

    static void validatePipelineBlock(Map record) {
        if (!record.containsKey('pipeline'))
            throw new IllegalArgumentException(
                "Record missing required 'pipeline' block. " +
                "Ensure your JSON includes: {\"pipeline\": {\"tool_version\": \"...\", \"dataset_id\": \"...\"}}"
            )
        def p = record.pipeline
        if (!p.dataset_id)
            throw new IllegalArgumentException(
                "Record 'pipeline.dataset_id' is empty. Each record needs a unique dataset identifier."
            )
        if (!p.tool_version)
            throw new IllegalArgumentException(
                "Record 'pipeline.tool_version' is empty. Specify the 10x tool version (e.g. 9.0.1)."
            )
    }

    static void validateLibraries(Map record) {
        if (!record.containsKey('libraries'))
            throw new IllegalArgumentException(
                "Record '${record.pipeline?.dataset_id}' missing 'libraries' section."
            )
        if (!(record.libraries instanceof List) || record.libraries.size() == 0)
            throw new IllegalArgumentException(
                "Record '${record.pipeline?.dataset_id}' has empty 'libraries' section."
            )
    }

    static void validateGex(Map record) {
        validatePipelineBlock(record)
        validateLibraries(record)

        if (!record.containsKey('gene-expression'))
            throw new IllegalArgumentException(
                "GEX record '${record.pipeline.dataset_id}' missing 'gene-expression' section."
            )
        if (!record['gene-expression'].reference)
            throw new IllegalArgumentException(
                "GEX record '${record.pipeline.dataset_id}' missing 'gene-expression.reference'."
            )
    }

    static void validateAtac(Map record) {
        validatePipelineBlock(record)
        validateLibraries(record)

        if (!record.containsKey('atac'))
            throw new IllegalArgumentException(
                "ATAC record '${record.pipeline.dataset_id}' missing 'atac' section."
            )
        if (!record['atac'].reference)
            throw new IllegalArgumentException(
                "ATAC record '${record.pipeline.dataset_id}' missing 'atac.reference'."
            )
    }

    static void validateMultiome(Map record) {
        validatePipelineBlock(record)
        validateLibraries(record)

        if (!record.containsKey('multiome'))
            throw new IllegalArgumentException(
                "Multiome record '${record.pipeline.dataset_id}' missing 'multiome' section."
            )
        if (!record['multiome'].reference)
            throw new IllegalArgumentException(
                "Multiome record '${record.pipeline.dataset_id}' missing 'multiome.reference'."
            )
    }

    static void validateVisium(Map record) {
        validatePipelineBlock(record)
        validateLibraries(record)

        if (!record.containsKey('gene-expression'))
            throw new IllegalArgumentException(
                "Visium record '${record.pipeline.dataset_id}' missing 'gene-expression' section."
            )
    }

    static void validateXenium(Map record) {
        validatePipelineBlock(record)

        if (!record.containsKey('xenium'))
            throw new IllegalArgumentException(
                "Xenium record '${record.pipeline.dataset_id}' missing 'xenium' section."
            )
        if (!record.xenium.action)
            throw new IllegalArgumentException(
                "Xenium record '${record.pipeline.dataset_id}' missing 'xenium.action' (resegment or relabel)."
            )
        if (!record.xenium.input_path)
            throw new IllegalArgumentException(
                "Xenium record '${record.pipeline.dataset_id}' missing 'xenium.input_path'."
            )
    }
}

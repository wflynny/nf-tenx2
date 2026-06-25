/*
 * Typed record definitions for nf-tenx2 (Nextflow 26.04 record types).
 *
 * The canonical unit of work is a record parsed from one input JSON file.
 * Historically this flowed through channels as a loose Groovy `Map`; these
 * record types give typed field access in workflow wiring while the pipeline
 * migrates off untyped maps.
 *
 * piloted on the GEX workflow only first. Other assays still pass with
 * raw `Map` records. Record declarations and field access work under the v2
 * parser with no feature flag; typed process ports need `nextflow.enable.types`.
 *
 * Input JSON uses hyphenated block keys (`gene-expression`, `probe-set`,
 * `create-bam`, ...) that are NOT valid record field names. Rather than map
 * them to/from underscore fields, each record carries the original parsed map
 * in `raw`. `recordToMap` returns `raw` as is, so JSON re-serialized for the
 * Python CSV converter / metadata should be identical to the original shape.
 * The typed fields below are just **VIEWS** over the same data so that nothing
 * mutates a record after construction.
 */

record Pipeline {
    dataset_id: String
    tool_version: String
    aggr_id: String
}

record TenxRecord {
    pipeline: Pipeline
    libraries: List<Map>
    samples: List<Map>
    gex: Map
    vdj: Map
    raw: Map
}

/*
 * Build a typed TenxRecord from a raw parsed-JSON map. Optional blocks
 * (`samples`, `vdj`, `aggr_id`) become null when absent.
 */
TenxRecord recordFromMap(Map raw) {
    new TenxRecord(
        pipeline: new Pipeline(
            dataset_id:   raw.pipeline.dataset_id,
            tool_version: raw.pipeline.tool_version,
            aggr_id:      raw.pipeline?.aggr_id
        ),
        libraries: (raw.libraries ?: []) as List<Map>,
        samples:   raw.samples as List<Map>,
        gex:       raw['gene-expression'] as Map,
        vdj:       raw.vdj as Map,
        raw:       raw
    )
}

/*
 * Serialize a TenxRecord back to its original hyphenated-key map. Returns the
 * stored `raw` map verbatim — lossless by construction.
 */
Map recordToMap(TenxRecord record) {
    return record.raw
}

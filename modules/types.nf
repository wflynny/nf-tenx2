/*
 * Typed record definitions for nf-tenx2 (Nextflow 26.04 record types).
 *
 * The canonical unit of work is a record parsed from one input JSON file.
 * Historically this flowed through channels as a loose Groovy `Map`; these
 * record types give typed field access in workflow wiring while the pipeline
 * migrates off untyped maps.
 *
 * `TenxNGSRecord` is the shared record for the four sequencing-based 10x assays
 * — GEX, ATAC, Multiome (Chromium) and Visium (spaceranger/spatial). They run
 * the same FASTQ → *ranger count (+aggr) skeleton and differ only in which
 * assay block is present; each block is a nullable view field below. The
 * imaging assay (Xenium) has a fundamentally different shape and still flows as
 * a raw `Map` (a future `TenxImagingRecord`). Record declarations and field
 * access work under the v2 parser with no feature flag; typed process ports
 * need `nextflow.enable.types`.
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

record TenxNGSRecord {
    pipeline: Pipeline
    libraries: List<Map>
    samples: List<Map>   // GEX multi
    gex: Map             // GEX, Visium (`gene-expression` block)
    vdj: Map             // GEX multi
    atac: Map            // ATAC
    multiome: Map        // Multiome (`cellranger-arc`)
    spatial: Map         // Visium
    raw: Map
}

/*
 * Build a typed TenxNGSRecord from a raw parsed-JSON map. Assay blocks that the
 * record's assay doesn't use (and optional blocks like `samples`/`vdj`/
 * `aggr_id`) become null when absent.
 */
TenxNGSRecord recordFromMap(Map raw) {
    new TenxNGSRecord(
        pipeline: new Pipeline(
            dataset_id:   raw.pipeline.dataset_id,
            tool_version: raw.pipeline.tool_version,
            aggr_id:      raw.pipeline?.aggr_id
        ),
        libraries: (raw.libraries ?: []) as List<Map>,
        samples:   raw.samples as List<Map>,
        gex:       raw['gene-expression'] as Map,
        vdj:       raw.vdj as Map,
        atac:      raw.atac as Map,
        multiome:  raw.multiome as Map,
        spatial:   raw.spatial as Map,
        raw:       raw
    )
}

/*
 * Serialize a TenxNGSRecord back to its original hyphenated-key map. Returns the
 * stored `raw` map verbatim — lossless by construction.
 */
Map recordToMap(TenxNGSRecord record) {
    return record.raw
}

/*
 * Record types for the four sequencing assays (GEX, ATAC, Multiome, Visium).
 * Xenium still passes plain Maps.
 *
 * Input JSON keys like `gene-expression` can't be record field names, so each
 * record keeps the parsed JSON in `raw`. The other fields are shortcuts into
 * it, and anything written back out as JSON or CSV uses `raw`.
 */

record Pipeline {
    dataset_id: String
    tool_version: String
    aggr_id: String?
}

record TenxNGSRecord {
    pipeline: Pipeline
    libraries: List<Map>
    samples: List<Map>?  // GEX multi
    gex: Map?            // GEX, Visium (`gene-expression` block)
    vdj: Map?            // GEX multi
    atac: Map?           // ATAC
    multiome: Map?       // Multiome (`cellranger-arc`)
    spatial: Map?        // Visium
    raw: Map
}

/*
 * Build a TenxNGSRecord from parsed JSON. Missing blocks are null.
 *
 * Use record(...), not `new TenxNGSRecord(...)`, and declare no return type.
 * Either one makes Nextflow hash the record differently on every launch, so
 * -resume never reuses a task (nextflow-io/nextflow#7884).
 */
def recordFromMap(raw) {
    record(
        pipeline: record(
            dataset_id:   raw.pipeline.dataset_id,
            tool_version: raw.pipeline.tool_version,
            aggr_id:      raw.pipeline?.aggr_id
        ),
        libraries: raw.libraries ?: [],
        samples:   raw.samples,
        gex:       raw['gene-expression'],
        vdj:       raw.vdj,
        atac:      raw.atac,
        multiome:  raw.multiome,
        spatial:   raw.spatial,
        raw:       raw
    )
}

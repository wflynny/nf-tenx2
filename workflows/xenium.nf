nextflow.enable.dsl = 2

include { XENIUMRANGER_RESEGMENT              } from "../modules/xeniumranger_resegment"
include { XENIUMRANGER_RELABEL                } from "../modules/xeniumranger_relabel"
include { MD5SUM                              } from "../modules/hash"
include { MD5SUM as MD5SUM_RELABEL            } from "../modules/hash"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { GENERATE_METADATA as GENERATE_METADATA_RELABEL } from "../modules/metadata"

/*
 * Xenium workflow — no FASTQ-based QC (Xenium input is a bundle, not FASTQs).
 *
 * Branches on the 'xenium.action' field in the record:
 *   - "resegment" → xeniumranger resegment
 *   - "relabel"   → xeniumranger relabel
 */
workflow XENIUM {
    take:
        records

    main:
        records
            .branch {
                resegment: it.xenium?.action == 'resegment'
                relabel:   it.xenium?.action == 'relabel'
            }
            .set { branched }

        // ── resegment path ──────────────────────────────────────────
        reseg_out  = XENIUMRANGER_RESEGMENT(branched.resegment)
        reseg_hash = MD5SUM(reseg_out.results)
        reseg_meta = GENERATE_METADATA(
            reseg_hash.hashes.join(reseg_out.results)
        )

        // ── relabel path ────────────────────────────────────────────
        relabel_out  = XENIUMRANGER_RELABEL(branched.relabel)
        relabel_hash = MD5SUM_RELABEL(relabel_out.results)
        relabel_meta = GENERATE_METADATA_RELABEL(
            relabel_hash.hashes.join(relabel_out.results)
        )

    emit:
        resegment_results = reseg_out.results
        relabel_results   = relabel_out.results
}

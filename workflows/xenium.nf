include { XENIUMRANGER_RESEGMENT              } from "../modules/xeniumranger_resegment"
include { XENIUMRANGER_RELABEL                } from "../modules/xeniumranger_relabel"
include { MD5SUM                              } from "../modules/hash"
include { MD5SUM as MD5SUM_RELABEL            } from "../modules/hash"
include { CAPTURE_WORKFLOW                    } from "../modules/metadata"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { GENERATE_METADATA as GENERATE_METADATA_RELABEL } from "../modules/metadata"
include { capture_workflow_json                           } from "../modules/utils"

workflow XENIUM {
    take:
        records
        pipeline_version

    main:
        validated = records.map { rec ->
            RecordValidator.validateXenium(rec)
            rec
        }

        wf_json = CAPTURE_WORKFLOW(capture_workflow_json(pipeline_version))

        validated
            .branch { rec ->
                resegment: rec.xenium?.action == 'resegment'
                relabel:   rec.xenium?.action == 'relabel'
            }
            .set { branched }

        // Resegment
        reseg_out  = XENIUMRANGER_RESEGMENT(branched.resegment)
        reseg_hash = MD5SUM(reseg_out.results)

        // No input checksums or metrics for xenium — pass empty placeholders
        reseg_meta_ch = reseg_hash.hashes
            .map { rec, output_checksums ->
                tuple(rec, output_checksums, file("NO_INPUT_CHECKSUMS"), file("NO_METRICS"))
            }

        GENERATE_METADATA(reseg_meta_ch, wf_json.json)

        // Relabel
        relabel_out  = XENIUMRANGER_RELABEL(branched.relabel)
        relabel_hash = MD5SUM_RELABEL(relabel_out.results)

        relabel_meta_ch = relabel_hash.hashes
            .map { rec, output_checksums ->
                tuple(rec, output_checksums, file("NO_INPUT_CHECKSUMS"), file("NO_METRICS"))
            }

        GENERATE_METADATA_RELABEL(relabel_meta_ch, wf_json.json)

    emit:
        resegment_results = reseg_out.results
        relabel_results   = relabel_out.results
}

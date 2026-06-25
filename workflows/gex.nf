/*
 * GEX workflow — handles all 10x single-cell gene expression assays.
 *
 * Supports optional aggregation: records with a matching `pipeline.aggr_id`
 * are grouped and fed to cellranger aggr after individual count/multi completes.
 */

include { CELLRANGER_MULTI                        } from "../modules/cellranger_multi"
include { CELLRANGER_COUNT                        } from "../modules/cellranger_count"
include { CELLRANGER_AGGR                         } from "../modules/cellranger_aggr"
include { RESOLVE_FASTQS                          } from "../modules/resolve_fastqs"
include { PUBLISH_FASTQS                          } from "../modules/publish_fastqs"
include { FASTQC                                  } from "../modules/fastqc"
include { MULTIQC_DATASET                         } from "../modules/multiqc"
include { MULTIQC                                 } from "../modules/multiqc"
include { MD5SUM                                  } from "../modules/hash"
include { MD5SUM as MD5SUM_MULTI                  } from "../modules/hash"
include { MD5SUM as MD5SUM_INPUTS                 } from "../modules/hash"
include { MD5SUM as MD5SUM_INPUTS_MULTI           } from "../modules/hash"
include { MD5SUM as MD5SUM_AGGR                   } from "../modules/hash"
include { CAPTURE_WORKFLOW                        } from "../modules/metadata"
include { GENERATE_METADATA                       } from "../modules/metadata"
include { GENERATE_METADATA as GENERATE_METADATA_MULTI } from "../modules/metadata"
include { RECORD_TO_JSON_FILE_TYPED as RECORD_TO_JSON_FILE       } from "../modules/file_parsing_typed"
include { RECORD_TO_JSON_FILE_TYPED as RECORD_TO_JSON_FILE_MULTI } from "../modules/file_parsing_typed"
include { JSON_TO_MULTI_CSV                       } from "../modules/file_parsing_typed"
include { JSON_TO_LIBRARIES_CSV                   } from "../modules/file_parsing"
include { recordFromMap                           } from "../modules/types"
include { capture_workflow_json                   } from "../modules/utils"


workflow GEX {
    take:
        records
        pipeline_version
        pubdir

    main:
        // ── Validate (on the raw map) then lift into a typed record ──
        //    Validation stays map-based (shared RecordValidator); the typed
        //    TenxRecord then flows through GEX wiring for typed field access.
        validated = records.map { raw ->
            RecordValidator.validateGex(raw)
            recordFromMap(raw)
        }

        // ── Workflow provenance (once per run) ──────────────────────
        wf_json = CAPTURE_WORKFLOW(capture_workflow_json(pipeline_version))

        // ── Resolve FASTQs on compute node ──────────────────────────
        resolved = RESOLVE_FASTQS(validated)

        // ── Publish FASTQs to client-accessible dir on a compute node
        //    (decoupled from analysis; nothing downstream depends on it).
        PUBLISH_FASTQS(resolved.fastq, pubdir)

        // ── Falco (FastQC) per file ─────────────────────────────────
        fastq_ch = resolved.fastq.flatMap { rec, fqs ->
            fqs.collect { fq -> tuple([dataset_id: rec.pipeline.dataset_id], fq) }
        }
        fastqc_out = FASTQC(fastq_ch)
        MULTIQC_DATASET(fastqc_out.results.groupTuple())
        MULTIQC(fastqc_out.results.map { _meta, qc_dir -> qc_dir }.collect())

        // ── Hash inputs (parallel with tools) ───────────────────────
        input_hash_branched = resolved.fastq
            .branch { rec, _fqs ->
                multi: rec.samples != null
                count: true
            }
        count_input_hashes = MD5SUM_INPUTS(input_hash_branched.count)
        multi_input_hashes = MD5SUM_INPUTS_MULTI(input_hash_branched.multi)

        // ── Branch records for tool execution ───────────────────────
        branched = validated
            .branch { rec ->
                multi: rec.samples != null
                count: true
            }

        // ── cellranger count ────────────────────────────────────────
        count_json = RECORD_TO_JSON_FILE(branched.count)
        count_csv  = JSON_TO_LIBRARIES_CSV(count_json)
        count_out  = CELLRANGER_COUNT(count_csv)
        count_output_hashes = MD5SUM(count_out.results)

        count_meta_ch = count_output_hashes.hashes
            .join(count_input_hashes.hashes)
            .join(count_out.metrics)
            .map { rec, out_md5, in_md5, metrics -> tuple(rec.raw, out_md5, in_md5, metrics) }
        GENERATE_METADATA(count_meta_ch, wf_json.json)

        // ── cellranger multi ────────────────────────────────────────
        multi_json = RECORD_TO_JSON_FILE_MULTI(branched.multi)
        multi_csv  = JSON_TO_MULTI_CSV(multi_json)
        multi_out  = CELLRANGER_MULTI(multi_csv)
        multi_output_hashes = MD5SUM_MULTI(multi_out.results)

        multi_meta_ch = multi_output_hashes.hashes
            .join(multi_input_hashes.hashes)
            .join(multi_out.metrics)
            .map { rec, out_md5, in_md5, metrics -> tuple(rec.raw, out_md5, in_md5, metrics) }
        GENERATE_METADATA_MULTI(multi_meta_ch, wf_json.json)

        // ── cellranger aggr (optional) ──────────────────────────────
        all_results = count_out.results.mix(multi_out.results)

        aggr_ch = all_results
            .filter { rec, _dir -> rec.pipeline.aggr_id != null }
            .map { rec, dir ->
                tuple(rec.pipeline.aggr_id, rec.pipeline.tool_version,
                      rec.pipeline.dataset_id, file("${dir}/molecule_info.h5"))
            }
            .groupTuple(by: [0, 1])

        CELLRANGER_AGGR(aggr_ch)
        MD5SUM_AGGR(CELLRANGER_AGGR.out.results)

    emit:
        // Lower the typed record back to its raw map at the workflow boundary so
        // downstream publishing (incl. the datasets.json index) is unchanged.
        results          = all_results.map { rec, dir -> tuple(rec.raw, dir) }
        metadata         = GENERATE_METADATA.out.metadata.mix(GENERATE_METADATA_MULTI.out.metadata)
        input_checksums  = count_input_hashes.hashes.mix(multi_input_hashes.hashes).map { rec, md5 -> tuple(rec.raw, md5) }
        fastqc           = fastqc_out.results
        multiqc_dataset  = MULTIQC_DATASET.out.html.mix(MULTIQC_DATASET.out.data)
        multiqc_run      = MULTIQC.out.html.mix(MULTIQC.out.data)
        aggr_results     = CELLRANGER_AGGR.out.results
}

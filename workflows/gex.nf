/*
 * GEX workflow — handles all 10x single-cell gene expression assays.
 */

include { CELLRANGER_MULTI                        } from "../modules/cellranger_multi"
include { CELLRANGER_COUNT                        } from "../modules/cellranger_count"
include { RESOLVE_FASTQS                          } from "../modules/resolve_fastqs"
include { FASTQC                                  } from "../modules/fastqc"
include { MULTIQC_DATASET                         } from "../modules/multiqc"
include { MULTIQC                                 } from "../modules/multiqc"
include { MD5SUM                                  } from "../modules/hash"
include { MD5SUM as MD5SUM_MULTI                  } from "../modules/hash"
include { MD5SUM as MD5SUM_INPUTS                 } from "../modules/hash"
include { MD5SUM as MD5SUM_INPUTS_MULTI           } from "../modules/hash"
include { CAPTURE_WORKFLOW                        } from "../modules/metadata"
include { GENERATE_METADATA                       } from "../modules/metadata"
include { GENERATE_METADATA as GENERATE_METADATA_MULTI } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                     } from "../modules/file_parsing"
include { RECORD_TO_JSON_FILE as RECORD_TO_JSON_FILE_MULTI } from "../modules/file_parsing"
include { JSON_TO_MULTI_CSV                       } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV                   } from "../modules/file_parsing"
include { is_multi_record; capture_workflow_json   } from "../modules/utils"


workflow GEX {
    take:
        records
        pipeline_version

    main:
        // ── Validate ────────────────────────────────────────────────
        validated = records.map { rec ->
            RecordValidator.validateGex(rec)
            rec
        }

        // ── Workflow provenance (once per run) ──────────────────────
        wf_json = CAPTURE_WORKFLOW(capture_workflow_json(pipeline_version))

        // ── Resolve FASTQs on compute node ──────────────────────────
        // Filters FASTQs by sample prefix on a compute node where
        // filesystem access is guaranteed. Everything that needs
        // individual files derives from this.
        resolved = RESOLVE_FASTQS(validated)

        // ── Falco (FastQC) per file ─────────────────────────────────
        fastq_ch = resolved.fastq.flatMap { rec, fqs ->
            fqs.collect { fq -> tuple([dataset_id: rec.pipeline.dataset_id], fq) }
        }
        fastqc_out = FASTQC(fastq_ch)
        MULTIQC_DATASET(fastqc_out.zip.groupTuple())
        MULTIQC(fastqc_out.zip.map { _meta, zip -> zip }.collect())

        // ── Hash inputs (parallel with tools) ───────────────────────
        resolved.fastq
            .branch { rec, _fqs ->
                multi: is_multi_record(rec)
                count: true
            }
            .set { input_hash_branched }
        count_input_hashes = MD5SUM_INPUTS(input_hash_branched.count)
        multi_input_hashes = MD5SUM_INPUTS_MULTI(input_hash_branched.multi)

        // ── Branch records for tool execution ───────────────────────
        // Tools only need the record — they find FASTQs from directory
        // paths in the record themselves.
        validated
            .branch { rec ->
                multi: is_multi_record(rec)
                count: true
            }
            .set { branched }

        // ── cellranger count ────────────────────────────────────────
        count_json = RECORD_TO_JSON_FILE(branched.count)
        count_csv  = JSON_TO_LIBRARIES_CSV(count_json)
        count_out  = CELLRANGER_COUNT(count_csv)
        count_output_hashes = MD5SUM(count_out.results)

        count_meta_ch = count_output_hashes.hashes
            .join(count_input_hashes.hashes)
            .join(count_out.metrics)
        GENERATE_METADATA(count_meta_ch, wf_json.json)

        // ── cellranger multi ────────────────────────────────────────
        multi_json = RECORD_TO_JSON_FILE_MULTI(branched.multi)
        multi_csv  = JSON_TO_MULTI_CSV(multi_json)
        multi_out  = CELLRANGER_MULTI(multi_csv)
        multi_output_hashes = MD5SUM_MULTI(multi_out.results)

        multi_meta_ch = multi_output_hashes.hashes
            .join(multi_input_hashes.hashes)
            .join(multi_out.metrics)
        GENERATE_METADATA_MULTI(multi_meta_ch, wf_json.json)

    emit:
        all_results  = count_out.results.mix(multi_out.results)
        multiqc_html = MULTIQC.out.html
}

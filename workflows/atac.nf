include { CELLRANGER_ATAC_COUNT               } from "../modules/cellranger-atac_count"
include { RESOLVE_FASTQS                      } from "../modules/resolve_fastqs"
include { FASTQC                              } from "../modules/fastqc"
include { MULTIQC_DATASET                     } from "../modules/multiqc"
include { MULTIQC                             } from "../modules/multiqc"
include { MD5SUM                              } from "../modules/hash"
include { MD5SUM as MD5SUM_INPUTS             } from "../modules/hash"
include { CAPTURE_WORKFLOW                    } from "../modules/metadata"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                 } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV               } from "../modules/file_parsing"
include { capture_workflow_json               } from "../modules/utils"

workflow ATAC {
    take:
        records
        pipeline_version

    main:
        validated = records.map { rec ->
            RecordValidator.validateAtac(rec)
            rec
        }

        wf_json = CAPTURE_WORKFLOW(capture_workflow_json(pipeline_version))

        // ── Resolve FASTQs on compute node ──────────────────────────
        resolved = RESOLVE_FASTQS(validated)

        // ── Falco (FastQC) per file ─────────────────────────────────
        fastq_ch = resolved.fastq.flatMap { rec, fqs ->
            fqs.collect { fq -> tuple([dataset_id: rec.pipeline.dataset_id], fq) }
        }
        fastqc_out = FASTQC(fastq_ch)
        MULTIQC_DATASET(fastqc_out.zip.groupTuple())
        MULTIQC(fastqc_out.zip.map { _meta, zip -> zip }.collect())

        // ── Hash inputs (parallel with tool) ────────────────────────
        input_hashes = MD5SUM_INPUTS(resolved.fastq)

        // ── Tool execution (uses record directly) ───────────────────
        tool_json = RECORD_TO_JSON_FILE(validated)
        tool_csv  = JSON_TO_LIBRARIES_CSV(tool_json)
        tool_out  = CELLRANGER_ATAC_COUNT(tool_csv)
        output_hashes = MD5SUM(tool_out.results)

        meta_ch = output_hashes.hashes
            .join(input_hashes.hashes)
            .join(tool_out.metrics)
        GENERATE_METADATA(meta_ch, wf_json.json)

    emit:
        results      = tool_out.results
        multiqc_html = MULTIQC.out.html
}

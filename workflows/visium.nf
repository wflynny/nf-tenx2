include { SPACERANGER_COUNT                   } from "../modules/spaceranger_count"
include { SPACERANGER_AGGR                    } from "../modules/spaceranger_aggr"
include { RESOLVE_FASTQS                      } from "../modules/resolve_fastqs"
include { PUBLISH_FASTQS                      } from "../modules/publish_fastqs"
include { FASTQC                              } from "../modules/fastqc"
include { MULTIQC_DATASET                     } from "../modules/multiqc"
include { MULTIQC                             } from "../modules/multiqc"
include { MD5SUM                              } from "../modules/hash"
include { MD5SUM as MD5SUM_INPUTS             } from "../modules/hash"
include { MD5SUM as MD5SUM_AGGR               } from "../modules/hash"
include { CAPTURE_WORKFLOW                    } from "../modules/metadata"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                 } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV               } from "../modules/file_parsing"
include { capture_workflow_json               } from "../modules/utils"

workflow VISIUM {
    take:
        records
        pipeline_version
        pubdir

    main:
        validated = records.map { rec ->
            RecordValidator.validateVisium(rec)
            rec
        }

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

        // ── Hash inputs (parallel with tool) ────────────────────────
        input_hashes = MD5SUM_INPUTS(resolved.fastq)

        // ── Tool execution ──────────────────────────────────────────
        tool_json = RECORD_TO_JSON_FILE(validated)
        tool_csv  = JSON_TO_LIBRARIES_CSV(tool_json)
        tool_out  = SPACERANGER_COUNT(tool_csv)
        output_hashes = MD5SUM(tool_out.results)

        meta_ch = output_hashes.hashes
            .join(input_hashes.hashes)
            .join(tool_out.metrics)
        GENERATE_METADATA(meta_ch, wf_json.json)

        // ── spaceranger aggr (optional) ─────────────────────────────
        aggr_ch = tool_out.results
            .filter { rec, _dir -> rec.pipeline.containsKey('aggr_id') }
            .map { rec, dir ->
                tuple(rec.pipeline.aggr_id, rec.pipeline.tool_version,
                      rec.pipeline.dataset_id, file("${dir}/molecule_info.h5"))
            }
            .groupTuple(by: [0, 1])

        SPACERANGER_AGGR(aggr_ch)
        MD5SUM_AGGR(SPACERANGER_AGGR.out.results)

    emit:
        results          = tool_out.results
        metadata         = GENERATE_METADATA.out.metadata
        input_checksums  = input_hashes.hashes
        fastqc           = fastqc_out.results
        multiqc_dataset  = MULTIQC_DATASET.out.html.mix(MULTIQC_DATASET.out.data)
        multiqc_run      = MULTIQC.out.html.mix(MULTIQC.out.data)
        aggr_results     = SPACERANGER_AGGR.out.results
}

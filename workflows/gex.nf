/*
 * GEX workflow — handles all 10x single-cell gene expression assays.
 */

include { CELLRANGER_MULTI                        } from "../modules/cellranger_multi"
include { CELLRANGER_COUNT                        } from "../modules/cellranger_count"
include { FASTQC                                  } from "../modules/fastqc"
include { MULTIQC                                 } from "../modules/multiqc"
include { MD5SUM                                  } from "../modules/hash"
include { MD5SUM as MD5SUM_MULTI                  } from "../modules/hash"
include { CAPTURE_WORKFLOW                        } from "../modules/metadata"
include { HASH_INPUTS                             } from "../modules/metadata"
include { HASH_INPUTS as HASH_INPUTS_MULTI        } from "../modules/metadata"
include { GENERATE_METADATA                       } from "../modules/metadata"
include { GENERATE_METADATA as GENERATE_METADATA_MULTI } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                     } from "../modules/file_parsing"
include { RECORD_TO_JSON_FILE as RECORD_TO_JSON_FILE_MULTI } from "../modules/file_parsing"
include { JSON_TO_MULTI_CSV                       } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV                   } from "../modules/file_parsing"
include { is_multi_record; extract_fastq_paths    } from "../modules/utils"


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
        wf_json = CAPTURE_WORKFLOW(pipeline_version)

        // ── Branch: multi vs count ──────────────────────────────────
        validated
            .branch { rec ->
                multi: is_multi_record(rec)
                count: true
            }
            .set { branched }

        // ── FASTQC on all records ───────────────────────────────────
        fastq_ch = validated
            .flatMap { rec ->
                def dataset_id = rec.pipeline.dataset_id
                extract_fastq_paths(rec).collect { fq_path ->
                    tuple(dataset_id, rec, file(fq_path))
                }
            }
            .groupTuple(by: 0)
            .map { dataset_id, recs, fq_dirs ->
                tuple(recs[0], fq_dirs)
            }

        fastqc_out = FASTQC(fastq_ch)
        MULTIQC(fastqc_out.zip.map { rec, zips -> zips }.flatten().collect())

        // ── cellranger count ────────────────────────────────────────
        count_json = RECORD_TO_JSON_FILE(branched.count)
        count_csv  = JSON_TO_LIBRARIES_CSV(count_json)
        count_out  = CELLRANGER_COUNT(count_csv)

        count_output_hashes = MD5SUM(count_out.results)
        count_input_hashes  = HASH_INPUTS(
            branched.count.map { rec ->
                tuple(rec, extract_fastq_paths(rec).collect { fq -> file(fq) })
            }
        )

        // Assemble: tuple(record, output_checksums, input_checksums, metrics)
        count_meta_ch = count_output_hashes.hashes  // (record, output_checksums.md5)
            .join(count_input_hashes.hashes)         // + input_checksums.md5
            .join(count_out.metrics)                  // + metrics_summary.csv

        GENERATE_METADATA(count_meta_ch, wf_json.json)

        // ── cellranger multi ────────────────────────────────────────
        multi_json = RECORD_TO_JSON_FILE_MULTI(branched.multi)
        multi_csv  = JSON_TO_MULTI_CSV(multi_json)
        multi_out  = CELLRANGER_MULTI(multi_csv)

        multi_output_hashes = MD5SUM_MULTI(multi_out.results)
        multi_input_hashes  = HASH_INPUTS_MULTI(
            branched.multi.map { rec ->
                tuple(rec, extract_fastq_paths(rec).collect { fq -> file(fq) })
            }
        )

        multi_meta_ch = multi_output_hashes.hashes
            .join(multi_input_hashes.hashes)
            .join(multi_out.metrics)

        GENERATE_METADATA_MULTI(multi_meta_ch, wf_json.json)

    emit:
        all_results  = count_out.results.mix(multi_out.results)
        multiqc_html = MULTIQC.out.html
}

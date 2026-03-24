/*
 * GEX workflow — handles all 10x single-cell gene expression assays:
 *
 * cellranger count:
 *   - 3' GEX, 3' GEX + AB, 3' AB only
 *   - 5' GEX, 5' GEX + AB
 *
 * cellranger multi (triggered by presence of 'samples' section):
 *   - 3' GEX + HTO, 3' GEX + HTO + AB
 *   - 5' GEX + VDJ, 5' GEX + VDJ + AB
 *   - 5' GEX + BEAM
 *   - Flex, Flex + AB
 *   - OCM, OCM + VDJ, OCM + AB
 */

include { CELLRANGER_MULTI                        } from "../modules/cellranger_multi"
include { CELLRANGER_COUNT                        } from "../modules/cellranger_count"
include { FASTQC                                  } from "../modules/fastqc"
include { MULTIQC                                 } from "../modules/multiqc"
include { MD5SUM                                  } from "../modules/hash"
include { MD5SUM as MD5SUM_MULTI                  } from "../modules/hash"
include { GENERATE_METADATA                       } from "../modules/metadata"
include { GENERATE_METADATA as GENERATE_METADATA_MULTI } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                     } from "../modules/file_parsing"
include { RECORD_TO_JSON_FILE as RECORD_TO_JSON_FILE_MULTI } from "../modules/file_parsing"
include { JSON_TO_MULTI_CSV                       } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV                   } from "../modules/file_parsing"
include { is_multi_record; extract_fastq_paths    } from "../modules/utils"


workflow GEX {
    take:
        records           // channel of parsed JSON record maps
        pipeline_version  // val: pipeline version string

    main:
        // ── Validate ────────────────────────────────────────────────
        validated = records.map { rec ->
            RecordValidator.validateGex(rec)
            rec
        }

        // ── Branch: multi vs count ──────────────────────────────────
        validated
            .branch { rec ->
                multi: is_multi_record(rec)
                count: true
            }
            .set { branched }

        // ── cellranger count path ───────────────────────────────────
        count_json = RECORD_TO_JSON_FILE(branched.count)
        count_csv  = JSON_TO_LIBRARIES_CSV(count_json)
        count_out  = CELLRANGER_COUNT(count_csv)

        count_hashes = MD5SUM(count_out.results)
        GENERATE_METADATA(
            count_hashes.hashes.join(count_out.results),
            pipeline_version
        )

        // ── cellranger multi path ───────────────────────────────────
        multi_json = RECORD_TO_JSON_FILE_MULTI(branched.multi)
        multi_csv  = JSON_TO_MULTI_CSV(multi_json)
        multi_out  = CELLRANGER_MULTI(multi_csv)

        multi_hashes = MD5SUM_MULTI(multi_out.results)
        GENERATE_METADATA_MULTI(
            multi_hashes.hashes.join(multi_out.results),
            pipeline_version
        )

        // ── FASTQC on all records ───────────────────────────────────
        // Extract FASTQ paths from every record, keyed by dataset_id for
        // reliable grouping (avoids map identity issues with groupTuple).
        fastq_ch = validated
            .flatMap { rec ->
                def dataset_id = rec.pipeline.dataset_id
                extract_fastq_paths(rec).collect { fq_path ->
                    tuple(dataset_id, rec, file(fq_path))
                }
            }
            .groupTuple(by: 0)        // group by dataset_id (string, safe equality)
            .map { dataset_id, recs, fq_dirs ->
                // After grouping, recs is a list of identical records — take first
                tuple(recs[0], fq_dirs)
            }

        fastqc_out = FASTQC(fastq_ch)

        // ── MultiQC aggregation ─────────────────────────────────────
        // Collect all FASTQC zip files across all records into one channel
        all_qc = fastqc_out.zip
            .map { rec, zips -> zips }
            .flatten()
            .collect()

        MULTIQC(all_qc)

    emit:
        // mix() merges the count and multi result channels so downstream
        // consumers get all results regardless of which branch ran
        all_results  = count_out.results.mix(multi_out.results)
        multiqc_html = MULTIQC.out.html
}

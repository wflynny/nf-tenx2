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
nextflow.enable.dsl = 2

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
        records   // channel of parsed JSON record maps

    main:
        // ── Branch: multi vs count ──────────────────────────────────
        records
            .branch {
                multi: is_multi_record(it)
                count: true
            }
            .set { branched }

        // ── cellranger count path ───────────────────────────────────
        count_json = RECORD_TO_JSON_FILE(branched.count)
        count_csv  = JSON_TO_LIBRARIES_CSV(count_json)
        count_out  = CELLRANGER_COUNT(count_csv)

        count_hashes   = MD5SUM(count_out.results)
        count_metadata = GENERATE_METADATA(
            count_hashes.hashes
                .join(count_out.results)
        )

        // ── cellranger multi path ───────────────────────────────────
        multi_json = RECORD_TO_JSON_FILE_MULTI(branched.multi)
        multi_csv  = JSON_TO_MULTI_CSV(multi_json)
        multi_out  = CELLRANGER_MULTI(multi_csv)

        multi_hashes   = MD5SUM_MULTI(multi_out.results)
        multi_metadata = GENERATE_METADATA_MULTI(
            multi_hashes.hashes
                .join(multi_out.results)
        )

        // ── FASTQC on all records ───────────────────────────────────
        // Extract FASTQ paths from every record and stage them
        fastq_ch = records
            .flatMap { record ->
                extract_fastq_paths(record).collect { fq_path ->
                    tuple(record, file(fq_path))
                }
            }
            // Group all fastq dirs per record so FASTQC gets them together
            .groupTuple()

        fastqc_out = FASTQC(fastq_ch)

        // ── MultiQC aggregation ─────────────────────────────────────
        all_qc = fastqc_out.zip
            .map { record, zips -> zips }
            .flatten()
            .collect()

        MULTIQC(all_qc)

    emit:
        count_results = count_out.results
        multi_results = multi_out.results
        multiqc_html  = MULTIQC.out.html
}

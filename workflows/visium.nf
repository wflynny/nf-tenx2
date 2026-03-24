nextflow.enable.dsl = 2

include { SPACERANGER_COUNT                   } from "../modules/spaceranger_count"
include { FASTQC                              } from "../modules/fastqc"
include { MULTIQC                             } from "../modules/multiqc"
include { MD5SUM                              } from "../modules/hash"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                 } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV               } from "../modules/file_parsing"
include { extract_fastq_paths                 } from "../modules/utils"

workflow VISIUM {
    take:
        records

    main:
        // ── Validate ────────────────────────────────────────────────
        validated = records.map { rec ->
            RecordValidator.validateVisium(rec)
            rec
        }
        // ── spaceranger count ───────────────────────────────────────
        sr_json = RECORD_TO_JSON_FILE(validated)
        sr_csv  = JSON_TO_LIBRARIES_CSV(sr_json)
        sr_out  = SPACERANGER_COUNT(sr_csv)

        hashes   = MD5SUM(sr_out.results)
        GENERATE_METADATA(
            hashes.hashes.join(sr_out.results)
        )

        // ── FASTQC ─────────────────────────────────────────────────
        fastq_ch = records
            .flatMap { record ->
                extract_fastq_paths(record).collect { fq_path ->
                    tuple(record, file(fq_path))
                }
            }
            .groupTuple()

        fastqc_out = FASTQC(fastq_ch)

        all_qc = fastqc_out.zip
            .map { record, zips -> zips }
            .flatten()
            .collect()

        MULTIQC(all_qc)

    emit:
        results      = sr_out.results
        multiqc_html = MULTIQC.out.html
}

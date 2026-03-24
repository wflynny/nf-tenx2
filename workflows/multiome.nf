nextflow.enable.dsl = 2

include { CELLRANGER_ARC_COUNT                } from "../modules/cellranger-arc_count"
include { FASTQC                              } from "../modules/fastqc"
include { MULTIQC                             } from "../modules/multiqc"
include { MD5SUM                              } from "../modules/hash"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                 } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV               } from "../modules/file_parsing"
include { extract_fastq_paths                 } from "../modules/utils"

workflow MULTIOME {
    take:
        records

    main:
        // ── Validate ────────────────────────────────────────────────
        validated = records.map { rec ->
            RecordValidator.validateMultiome(rec)
            rec
        }
        // ── cellranger-arc count ────────────────────────────────────
        arc_json = RECORD_TO_JSON_FILE(validated)
        arc_csv  = JSON_TO_LIBRARIES_CSV(arc_json)
        arc_out  = CELLRANGER_ARC_COUNT(arc_csv)

        hashes   = MD5SUM(arc_out.results)
        GENERATE_METADATA(
            hashes.hashes.join(arc_out.results)
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
        results      = arc_out.results
        multiqc_html = MULTIQC.out.html
}

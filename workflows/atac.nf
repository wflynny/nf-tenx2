nextflow.enable.dsl = 2

include { CELLRANGER_ATAC_COUNT               } from "../modules/cellranger-atac_count"
include { FASTQC                              } from "../modules/fastqc"
include { MULTIQC                             } from "../modules/multiqc"
include { MD5SUM                              } from "../modules/hash"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                 } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV               } from "../modules/file_parsing"
include { extract_fastq_paths                 } from "../modules/utils"

workflow ATAC {
    take:
        records

    main:
        // ── cellranger-atac count ───────────────────────────────────
        atac_json = RECORD_TO_JSON_FILE(records)
        atac_csv  = JSON_TO_LIBRARIES_CSV(atac_json)
        atac_out  = CELLRANGER_ATAC_COUNT(atac_csv)

        hashes   = MD5SUM(atac_out.results)
        metadata = GENERATE_METADATA(
            hashes.hashes.join(atac_out.results)
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
        results     = atac_out.results
        multiqc_html = MULTIQC.out.html
}

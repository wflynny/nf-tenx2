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
        pipeline_version

    main:
        validated = records.map { rec ->
            RecordValidator.validateVisium(rec)
            rec
        }

        sr_json = RECORD_TO_JSON_FILE(validated)
        sr_csv  = JSON_TO_LIBRARIES_CSV(sr_json)
        sr_out  = SPACERANGER_COUNT(sr_csv)

        hashes = MD5SUM(sr_out.results)
        GENERATE_METADATA(
            hashes.hashes.join(sr_out.results),
            pipeline_version
        )

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

        all_qc = fastqc_out.zip
            .map { rec, zips -> zips }
            .flatten()
            .collect()

        MULTIQC(all_qc)

    emit:
        results      = sr_out.results
        multiqc_html = MULTIQC.out.html
}

include { CELLRANGER_ATAC_COUNT                             } from "../modules/cellranger-atac_count"
include { FASTQC                              } from "../modules/fastqc"
include { MULTIQC                             } from "../modules/multiqc"
include { MD5SUM                              } from "../modules/hash"
include { CAPTURE_WORKFLOW                    } from "../modules/metadata"
include { HASH_INPUTS                         } from "../modules/metadata"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                 } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV               } from "../modules/file_parsing"
include { extract_fastq_paths                 } from "../modules/utils"

workflow ATAC {
    take:
        records
        pipeline_version

    main:
        validated = records.map { rec ->
            RecordValidator.validateAtac(rec)
            rec
        }

        wf_json = CAPTURE_WORKFLOW(pipeline_version)

        fastq_ch = validated
            .flatMap { rec ->
                def dataset_id = rec.pipeline.dataset_id
                extract_fastq_paths(rec).collectMany { fq_dir ->
                    file("${fq_dir}/**/*.fastq.gz").collect { fq_file ->
                        tuple([dataset_id: dataset_id], fq_file)
                    }
                }
            }

        fastqc_out = FASTQC(fastq_ch)
        MULTIQC(fastqc_out.zip.map { meta, zip -> zip }.collect())

        tool_json = RECORD_TO_JSON_FILE(validated)
        tool_csv  = JSON_TO_LIBRARIES_CSV(tool_json)
        tool_out  = CELLRANGER_ATAC_COUNT(tool_csv)

        output_hashes = MD5SUM(tool_out.results)
        input_hashes  = HASH_INPUTS(
            validated.map { rec ->
                tuple(rec, extract_fastq_paths(rec).collect { fq -> file(fq) })
            }
        )

        meta_ch = output_hashes.hashes
            .join(input_hashes.hashes)
            .join(tool_out.metrics)

        GENERATE_METADATA(meta_ch, wf_json.json)

    emit:
        results      = tool_out.results
        multiqc_html = MULTIQC.out.html
}

include { CELLRANGER_ARC_COUNT                             } from "../modules/cellranger-arc_count"
include { FASTQC                              } from "../modules/fastqc"
include { MULTIQC_DATASET                     } from "../modules/multiqc"
include { MULTIQC                             } from "../modules/multiqc"
include { MD5SUM                              } from "../modules/hash"
include { CAPTURE_WORKFLOW                    } from "../modules/metadata"
include { HASH_INPUTS                         } from "../modules/metadata"
include { GENERATE_METADATA                   } from "../modules/metadata"
include { RECORD_TO_JSON_FILE                 } from "../modules/file_parsing"
include { JSON_TO_LIBRARIES_CSV               } from "../modules/file_parsing"
include { PUBLISH_FASTQS                     } from "../modules/publish_fastqs"
include { extract_fastq_paths; extract_sample_prefixes; capture_workflow_json } from "../modules/utils"

workflow MULTIOME {
    take:
        records
        pipeline_version

    main:
        validated = records.map { rec ->
            RecordValidator.validateMultiome(rec)
            rec
        }

        wf_json = CAPTURE_WORKFLOW(capture_workflow_json(pipeline_version))

        // ── Filter FASTQs once per record ───────────────────────────
        record_fastqs = validated.map { rec ->
            def prefixes = extract_sample_prefixes(rec)
            def fqs = extract_fastq_paths(rec).collectMany { d ->
                files("${d}/**/*.fastq.gz").findAll { f -> prefixes.any { p -> f.name.startsWith(p) } }
            }
            tuple(rec, fqs)
        }

        // ── Falco (FastQC) on individual FASTQ files ────────────────
        fastq_ch = record_fastqs.flatMap { rec, fqs ->
            fqs.collect { fq -> tuple([dataset_id: rec.pipeline.dataset_id], fq) }
        }

        fastqc_out = FASTQC(fastq_ch)

        // Per-dataset MultiQC: group zips by dataset_id
        dataset_qc = fastqc_out.zip
            .groupTuple()
        MULTIQC_DATASET(dataset_qc)

        // Run-level MultiQC: collect all zips
        MULTIQC(fastqc_out.zip.map { meta, zip -> zip }.collect())

        // ── Publish sample-filtered FASTQs per dataset ──────────────
        PUBLISH_FASTQS(fastq_ch.groupTuple())

        tool_json = RECORD_TO_JSON_FILE(record_fastqs.map { rec, _fqs -> rec })
        tool_csv  = JSON_TO_LIBRARIES_CSV(tool_json)
        tool_out  = CELLRANGER_ARC_COUNT(tool_csv)

        output_hashes = MD5SUM(tool_out.results)
        input_hashes  = HASH_INPUTS(record_fastqs)

        meta_ch = output_hashes.hashes
            .join(input_hashes.hashes)
            .join(tool_out.metrics)

        GENERATE_METADATA(meta_ch, wf_json.json)

    emit:
        results      = tool_out.results
        multiqc_html = MULTIQC.out.html
}

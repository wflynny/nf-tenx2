/*
 * GEX workflow — handles all 10x single-cell gene expression assays.
 */

include { CELLRANGER_MULTI                        } from "../modules/cellranger_multi"
include { CELLRANGER_COUNT                        } from "../modules/cellranger_count"
include { FASTQC                                  } from "../modules/fastqc"
include { MULTIQC_DATASET                         } from "../modules/multiqc"
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
include { PUBLISH_FASTQS                              } from "../modules/publish_fastqs"
include { is_multi_record; extract_fastq_paths; extract_sample_prefixes; capture_workflow_json } from "../modules/utils"


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
        wf_json = CAPTURE_WORKFLOW(capture_workflow_json(pipeline_version))

        // ── Branch: multi vs count ──────────────────────────────────
        validated
            .branch { rec ->
                multi: is_multi_record(rec)
                count: true
            }
            .set { branched }

        // ── Falco (FastQC) on individual FASTQ files ────────────────
        // Expand each record's FASTQ dirs into individual .fastq.gz files,
        // filtered to only those matching this record's sample prefixes.
        fastq_ch = validated
            .flatMap { rec ->
                def dataset_id = rec.pipeline.dataset_id
                def prefixes = extract_sample_prefixes(rec)
                extract_fastq_paths(rec).collectMany { fq_dir ->
                    files("${fq_dir}/**/*.fastq.gz")
                        .findAll { fq_file -> prefixes.any { prefix -> fq_file.name.startsWith(prefix) } }
                        .collect { fq_file -> tuple([dataset_id: dataset_id], fq_file) }
                }
            }

        fastq_ch.view() // Debugging

        fastqc_out = FASTQC(fastq_ch)

        // Per-dataset MultiQC: group zips by dataset_id
        dataset_qc = fastqc_out.zip
            .groupTuple()
        MULTIQC_DATASET(dataset_qc)

        // Run-level MultiQC: collect all zips
        MULTIQC(fastqc_out.zip.map { meta, zip -> zip }.collect())

        // ── Publish sample-filtered FASTQs per dataset ──────────────
        PUBLISH_FASTQS(fastq_ch.groupTuple())

        // ── cellranger count ────────────────────────────────────────
        count_json = RECORD_TO_JSON_FILE(branched.count)
        count_csv  = JSON_TO_LIBRARIES_CSV(count_json)
        count_out  = CELLRANGER_COUNT(count_csv)

        count_output_hashes = MD5SUM(count_out.results)
        count_input_hashes  = HASH_INPUTS(
            branched.count.map { rec ->
                def prefixes = extract_sample_prefixes(rec)
                def fqs = extract_fastq_paths(rec).collectMany { d ->
                    files("${d}/**/*.fastq.gz").findAll { f -> prefixes.any { p -> f.name.startsWith(p) } }
                }
                tuple(rec, fqs)
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
                def prefixes = extract_sample_prefixes(rec)
                def fqs = extract_fastq_paths(rec).collectMany { d ->
                    files("${d}/**/*.fastq.gz").findAll { f -> prefixes.any { p -> f.name.startsWith(p) } }
                }
                tuple(rec, fqs)
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

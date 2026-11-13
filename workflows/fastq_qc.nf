/*
 * FASTQ QC shared by the four NGS workflows: Falco (FastQC) per file, then a
 * MultiQC report per dataset and one for the whole run.
 *
 * take: tuple(record, fastq dir) from RESOLVE_FASTQS, where each FASTQ sits in
 *       fastq/<source dir>/.
 */

include { FASTQC          } from "../modules/fastqc"
include { MULTIQC_DATASET } from "../modules/multiqc"
include { MULTIQC         } from "../modules/multiqc"

workflow FASTQ_QC {
    take:
        fastqs

    main:
        fastq_ch = fastqs.flatMap { rec, fq_dir ->
            files("${fq_dir}/**.fastq.gz").collect { fq ->
                tuple([dataset_id: rec.pipeline.dataset_id, run: fq.parent.name], fq)
            }
        }
        FASTQC(fastq_ch)
        MULTIQC_DATASET(FASTQC.out.results.map { meta, qc_dir -> tuple([dataset_id: meta.dataset_id], qc_dir) }.groupTuple())
        MULTIQC(FASTQC.out.results.map { _meta, qc_dir -> qc_dir }.collect())

    emit:
        fastqc          = FASTQC.out.results
        multiqc_dataset = MULTIQC_DATASET.out.html.mix(MULTIQC_DATASET.out.data)
        multiqc_run     = MULTIQC.out.html.mix(MULTIQC.out.data)
}

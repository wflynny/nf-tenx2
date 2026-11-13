/*
 * Copy resolved FASTQs to the per-dataset client-accessible publish dir.
 *
 * RESOLVE_FASTQS only stages symlinks inside the work dir. The actual
 * client handoff (service-account-owned source -> client-readable dest)
 * needs a real byte-for-byte copy. Doing that via `publishDir mode: 'copy'`
 * runs the copy on the head node and saturates NFS bandwidth, starving
 * Nextflow's task submitter for many minutes per submission when datasets
 * are ~TB-scale.
 *
 * This process moves the copy off the head node and onto a compute node,
 * with parallel streams. Nothing depends on its output, so the analysis
 * fan-out (FASTQC, MD5SUM, *RANGER) runs in parallel with the copy.
 */
process PUBLISH_FASTQS {
    label 'process_low'

    input:
        tuple val(record), path(fastq_dir)
        val(pubdir)

    output:
        tuple val(record), path("manifest.txt"), emit: manifest

    script:
    def datasetId = record.pipeline.dataset_id
    def dest      = "${pubdir}/${datasetId}/fastq"
    def parallel  = Math.max(task.cpus * 2, 4)
    """
    mkdir -p '${dest}'
    # Keep the fastq/<source dir>/ subfolders in the destination.
    cd ${fastq_dir}
    find -L . -mindepth 1 -type d -exec mkdir -p '${dest}/{}' \\;
    find -L . -type f -name '*.fastq.gz' -print0 \\
        | xargs -0 -P ${parallel} -I{} cp -L {} '${dest}/{}'
    cd - > /dev/null
    (cd '${dest}' && find . -name '*.fastq.gz' | sort) > manifest.txt
    """

    stub:
    """
    touch manifest.txt
    """
}

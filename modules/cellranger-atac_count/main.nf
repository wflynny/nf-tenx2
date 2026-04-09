include { calc_localmem } from "../utils"

process CELLRANGER_ATAC_COUNT {

    label 'process_high'

    module "cellranger-atac/${record.pipeline.tool_version}"

    input:
        tuple val(record), path("libraries.csv")

    output:
        tuple val(record), path("cellranger-atac"),                       emit: results
        tuple val(record), path("cellranger-atac/summary.csv"),           emit: metrics

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def cmd        = CommandBuilder.cellrangerAtacCount(record, task.cpus, localmem)
    """
    ${cmd}

    mkdir -p cellranger-atac/_files
    mv ${dataset_id}/_* cellranger-atac/_files/ || true
    mv ${dataset_id}/*.tgz cellranger-atac/ || true
    mv ${dataset_id}/outs/* cellranger-atac/
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    """
    mkdir -p cellranger-atac/_files
    mkdir -p cellranger-atac/filtered_peak_bc_matrix
    mkdir -p cellranger-atac/analysis

    touch cellranger-atac/${dataset_id}.mri.tgz
    touch cellranger-atac/web_summary.html
    touch cellranger-atac/fragments.tsv.gz
    touch cellranger-atac/fragments.tsv.gz.tbi
    touch cellranger-atac/singlecell.csv
    touch cellranger-atac/peaks.bed
    echo 'metric,value' > cellranger-atac/summary.csv
    echo 'Estimated number of cells,5000' >> cellranger-atac/summary.csv
    """
}

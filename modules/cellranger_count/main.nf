include { calc_localmem } from "../utils"

process CELLRANGER_COUNT {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger/${record.pipeline.tool_version}" }

    input:
        tuple val(record), path("libraries.csv")

    output:
        tuple val(record), path("cellranger"),                           emit: results
        tuple val(record), path("cellranger/collected_metrics.json"),    emit: metrics

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def cmd        = CommandBuilder.cellrangerCount(record, task.cpus, localmem)
    """
    ${cmd}

    mkdir -p cellranger/_files
    mv libraries.csv cellranger/
    mv ${dataset_id}/_* cellranger/_files/ || true
    mv ${dataset_id}/*.tgz cellranger/ || true
    mv ${dataset_id}/outs/* cellranger/

    collect_metrics.py \\
        --pipestance-dir ${dataset_id} \\
        --tool-dir cellranger \\
        --out cellranger/collected_metrics.json
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    """
    mkdir -p cellranger/_files
    mkdir -p cellranger/filtered_feature_bc_matrix
    mkdir -p cellranger/raw_feature_bc_matrix
    mkdir -p cellranger/analysis

    cp libraries.csv cellranger/

    touch cellranger/${dataset_id}.mri.tgz
    touch cellranger/web_summary.html
    touch cellranger/molecule_info.h5
    touch cellranger/filtered_feature_bc_matrix/barcodes.tsv.gz
    touch cellranger/filtered_feature_bc_matrix/features.tsv.gz
    touch cellranger/filtered_feature_bc_matrix/matrix.mtx.gz
    touch cellranger/raw_feature_bc_matrix/barcodes.tsv.gz
    touch cellranger/raw_feature_bc_matrix/features.tsv.gz
    touch cellranger/raw_feature_bc_matrix/matrix.mtx.gz
    touch cellranger/cloupe.cloupe

    echo '{"summary":{}}' > cellranger/summary.json
    echo 'Estimated Number of Cells,Mean Reads per Cell' > cellranger/metrics_summary.csv
    echo '5000,50000' >> cellranger/metrics_summary.csv
    echo '{"metrics_summary.csv":{"Estimated Number of Cells":"5000","Mean Reads per Cell":"50000"}}' > cellranger/collected_metrics.json
    """
}

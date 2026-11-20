nextflow.enable.types = true

include { calc_localmem } from "../utils"
include { TenxNGSRecord    } from "../types"

process CELLRANGER_COUNT {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger/${record.pipeline.tool_version}" }

    input:
        tuple(record: TenxNGSRecord, libraries_csv: Path)

    stage:
        stageAs libraries_csv, 'libraries.csv'

    output:
        results = tuple(record, file("cellranger"))

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def rec_json = groovy.json.JsonOutput.toJson(record.raw)
    """
    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool cellranger-count --cpus ${task.cpus} --mem ${localmem} > 10x_command.sh <<- 'HEREDOC'
    ${rec_json}
    HEREDOC
    cat 10x_command.sh
    bash 10x_command.sh

    mkdir -p cellranger/_files
    mv libraries.csv cellranger/
    mv ${dataset_id}/_* cellranger/_files/ || true
    mv ${dataset_id}/*.tgz cellranger/ || true
    mv ${dataset_id}/outs/* cellranger/
    """

    stub:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson(record.raw)
    def dataset_id = record.pipeline.dataset_id
    """
    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool cellranger-count --cpus ${task.cpus} --mem ${localmem} > 10x_command.sh <<- 'HEREDOC'
    ${rec_json}
    HEREDOC
    cat 10x_command.sh

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
    """
}

nextflow.enable.types = true

include { calc_localmem } from "../utils"
include { TenxNGSRecord    } from "../types"

process CELLRANGER_MULTI {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger/${record.pipeline.tool_version}" }

    input:
        tuple(record: TenxNGSRecord, multi_csv: Path)

    stage:
        stageAs multi_csv, 'multi.csv'

    output:
        results = tuple(record, file("cellranger-multi"))

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def rec_json = groovy.json.JsonOutput.toJson(record.raw)
    """
    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool cellranger-multi --cpus ${task.cpus} --mem ${localmem} > 10x_command.sh <<- 'HEREDOC'
    ${rec_json}
    HEREDOC
    cat 10x_command.sh
    bash 10x_command.sh

    mkdir -p cellranger-multi/_files
    mv multi.csv cellranger-multi/
    mv ${dataset_id}/_* cellranger-multi/_files/ || true
    mv ${dataset_id}/*.tgz cellranger-multi/ || true
    mv ${dataset_id}/outs/* cellranger-multi/
    """

    stub:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson(record.raw)
    def dataset_id = record.pipeline.dataset_id
    // Singleplex multi (samples: []) writes per_sample_outs/<dataset_id>.
    def sample_ids = record.samples != null && record.samples.size() > 0 ? record.samples.collect { s -> s.sample_id ?: 'sample1' } : [dataset_id]
    def mkdir_cmds = sample_ids.collect { sid ->
        """
        mkdir -p cellranger-multi/per_sample_outs/${sid}
        echo 'Estimated Number of Cells,Mean Reads per Cell' > cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        echo '3000,40000' >> cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        touch cellranger-multi/per_sample_outs/${sid}/web_summary.html
        """
    }.join('\n')
    """
    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool cellranger-multi --cpus ${task.cpus} --mem ${localmem} > 10x_command.sh <<- 'HEREDOC'
    ${rec_json}
    HEREDOC
    cat 10x_command.sh

    mkdir -p cellranger-multi/_files
    mkdir -p cellranger-multi/multi/count/raw_feature_bc_matrix
    mkdir -p cellranger-multi/multi/count/filtered_feature_bc_matrix

    cp multi.csv cellranger-multi/

    touch cellranger-multi/${dataset_id}.mri.tgz
    touch cellranger-multi/multi/count/raw_feature_bc_matrix/barcodes.tsv.gz
    touch cellranger-multi/multi/count/filtered_feature_bc_matrix/barcodes.tsv.gz

    ${mkdir_cmds}

    """
}

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
    run_10x.py --tool cellranger-multi --cpus ${task.cpus} --mem ${localmem} <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

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
    def sample_ids = record.samples != null ? record.samples.collect { s -> s.sample_id ?: 'sample1' } : ['sample1']
    def mkdir_cmds = sample_ids.collect { sid ->
        """
    run_10x.py --tool cellranger-multi --cpus ${task.cpus} --mem ${localmem} --dry-run <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

        mkdir -p cellranger-multi/per_sample_outs/${sid}
        echo 'Estimated Number of Cells,Mean Reads per Cell' > cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        echo '3000,40000' >> cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        touch cellranger-multi/per_sample_outs/${sid}/web_summary.html
        """
    }.join('\n')
    """
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

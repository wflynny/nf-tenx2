nextflow.enable.types = true

include { calc_localmem } from "../utils"

process CELLRANGER_ATAC_AGGR {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger-atac/${version}" }

    input:
        tuple(aggr_id: String, version: String, reference: String, dataset_ids: List<String>,
              fragments: List<Path>, cells: List<Path>)

    stage:
        stageAs fragments, '?_fragments.tsv.gz'
        stageAs cells, '?_singlecell.csv'

    output:
        results = tuple(aggr_id, file("cellranger-atac-aggr"))

    script:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson([pipeline: [dataset_id: aggr_id, tool_version: version], reference: reference])
    def csv_content = (['library_id,fragments,cells'] + [dataset_ids, fragments, cells].transpose().collect { row -> row.join(',') }).join('\\n')
    """
    printf '${csv_content}\\n' > aggr.csv

    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool cellranger-atac-aggr --cpus ${task.cpus} --mem ${localmem} > 10x_command.sh <<- 'HEREDOC'
    ${rec_json}
    HEREDOC
    cat 10x_command.sh
    bash 10x_command.sh

    mkdir -p cellranger-atac-aggr/_files
    mv ${aggr_id}/_* cellranger-atac-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-atac-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-atac-aggr/
    """

    stub:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson([pipeline: [dataset_id: aggr_id, tool_version: version], reference: reference])
    """
    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool cellranger-atac-aggr --cpus ${task.cpus} --mem ${localmem} > 10x_command.sh <<- 'HEREDOC'
    ${rec_json}
    HEREDOC
    cat 10x_command.sh

    mkdir -p cellranger-atac-aggr/_files
    touch cellranger-atac-aggr/web_summary.html
    """
}

nextflow.enable.types = true

include { calc_localmem } from "../utils"

process SPACERANGER_AGGR {

    label 'process_high'

    module { task.executor == 'local' ? '' : "spaceranger/${version}" }

    input:
        tuple(aggr_id: String, version: String, dataset_ids: List<String>, mol_h5s: List<Path>)

    stage:
        stageAs mol_h5s, '?_molecule_info.h5'

    output:
        results = tuple(aggr_id, file("spaceranger-aggr"))

    script:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson([pipeline: [dataset_id: aggr_id, tool_version: version]])
    def csv_content = (['sample_id,molecule_h5'] + [dataset_ids, mol_h5s].transpose().collect { row -> row.join(',') }).join('\\n')
    """
    printf '${csv_content}\\n' > aggr.csv

    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool spaceranger-aggr --cpus ${task.cpus} --mem ${localmem} <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

    mkdir -p spaceranger-aggr/_files
    mv ${aggr_id}/_* spaceranger-aggr/_files/ || true
    mv ${aggr_id}/*.tgz spaceranger-aggr/ || true
    mv ${aggr_id}/outs/* spaceranger-aggr/
    """

    stub:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson([pipeline: [dataset_id: aggr_id, tool_version: version]])
    """
    # tenx_cli.json md5: ${task.ext.tenx_rules_md5}
    run_10x.py --tool spaceranger-aggr --cpus ${task.cpus} --mem ${localmem} --dry-run <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

    mkdir -p spaceranger-aggr/_files
    touch spaceranger-aggr/web_summary.html
    """
}

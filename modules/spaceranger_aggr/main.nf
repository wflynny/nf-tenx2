include { calc_localmem } from "../utils"

process SPACERANGER_AGGR {

    label 'process_high'

    module { task.executor == 'local' ? '' : "spaceranger/${version}" }

    input:
        tuple val(aggr_id), val(version), val(dataset_ids), path(mol_h5s, stageAs: '?_molecule_info.h5')

    output:
        tuple val(aggr_id), path("spaceranger-aggr"),                        emit: results
        tuple val(aggr_id), path("spaceranger-aggr/collected_metrics.json"), emit: metrics

    script:
    def localmem = calc_localmem(task.memory)
    def cmd      = CommandBuilder.spacerangerAggr(aggr_id, task.cpus, localmem)
    def csv_lines = ["sample_id,molecule_h5"]
    def h5_list = mol_h5s instanceof List ? mol_h5s : [mol_h5s]
    dataset_ids.eachWithIndex { did, i -> csv_lines << "${did},${h5_list[i]}" }
    def csv_content = csv_lines.join('\\n')
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p spaceranger-aggr/_files
    mv ${aggr_id}/_* spaceranger-aggr/_files/ || true
    mv ${aggr_id}/*.tgz spaceranger-aggr/ || true
    mv ${aggr_id}/outs/* spaceranger-aggr/

    collect_metrics.py \\
        --pipestance-dir ${aggr_id} \\
        --tool-dir spaceranger-aggr \\
        --out spaceranger-aggr/collected_metrics.json
    """

    stub:
    """
    mkdir -p spaceranger-aggr/_files
    touch spaceranger-aggr/web_summary.html
    echo '{"aggregated":true}' > spaceranger-aggr/collected_metrics.json
    """
}

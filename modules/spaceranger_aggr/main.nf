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
        metrics = tuple(aggr_id, file("spaceranger-aggr/collected_metrics.json"))

    script:
    def localmem = calc_localmem(task.memory)
    def cmd      = CommandBuilder.spacerangerAggr(aggr_id, task.cpus, localmem)
    def csv_lines = ["sample_id,molecule_h5"]
    dataset_ids.eachWithIndex { did, i -> csv_lines << "${did},${mol_h5s[i]}" }
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

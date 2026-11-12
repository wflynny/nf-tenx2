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
    def cmd      = CommandBuilder.spacerangerAggr(aggr_id, task.cpus, localmem)
    def csv_content = CommandBuilder.spacerangerAggrCsv(dataset_ids, mol_h5s)
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p spaceranger-aggr/_files
    mv ${aggr_id}/_* spaceranger-aggr/_files/ || true
    mv ${aggr_id}/*.tgz spaceranger-aggr/ || true
    mv ${aggr_id}/outs/* spaceranger-aggr/
    """

    stub:
    """
    mkdir -p spaceranger-aggr/_files
    touch spaceranger-aggr/web_summary.html
    """
}

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
    def cmd      = CommandBuilder.cellrangerAtacAggr(aggr_id, reference, task.cpus, localmem)
    def csv_content = CommandBuilder.cellrangerAtacAggrCsv(dataset_ids, fragments, cells)
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p cellranger-atac-aggr/_files
    mv ${aggr_id}/_* cellranger-atac-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-atac-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-atac-aggr/
    """

    stub:
    """
    mkdir -p cellranger-atac-aggr/_files
    touch cellranger-atac-aggr/web_summary.html
    """
}

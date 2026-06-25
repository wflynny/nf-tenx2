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
        metrics = tuple(aggr_id, file("cellranger-atac-aggr/collected_metrics.json"))

    script:
    def localmem = calc_localmem(task.memory)
    def cmd      = CommandBuilder.cellrangerAtacAggr(aggr_id, reference, task.cpus, localmem)
    def csv_lines = ["library_id,fragments,cells"]
    dataset_ids.eachWithIndex { did, i -> csv_lines << "${did},${fragments[i]},${cells[i]}" }
    def csv_content = csv_lines.join('\\n')
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p cellranger-atac-aggr/_files
    mv ${aggr_id}/_* cellranger-atac-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-atac-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-atac-aggr/

    collect_metrics.py \\
        --pipestance-dir ${aggr_id} \\
        --tool-dir cellranger-atac-aggr \\
        --out cellranger-atac-aggr/collected_metrics.json
    """

    stub:
    """
    mkdir -p cellranger-atac-aggr/_files
    touch cellranger-atac-aggr/web_summary.html
    echo '{"aggregated":true}' > cellranger-atac-aggr/collected_metrics.json
    """
}

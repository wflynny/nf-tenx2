include { calc_localmem } from "../utils"

process CELLRANGER_ATAC_AGGR {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger-atac/${version}" }

    input:
        tuple val(aggr_id), val(version), val(reference), val(dataset_ids),
              path(fragments, stageAs: '?_fragments.tsv.gz'),
              path(cells, stageAs: '?_singlecell.csv')

    output:
        tuple val(aggr_id), path("cellranger-atac-aggr"),                        emit: results
        tuple val(aggr_id), path("cellranger-atac-aggr/collected_metrics.json"), emit: metrics

    script:
    def localmem = calc_localmem(task.memory)
    def cmd      = CommandBuilder.cellrangerAtacAggr(aggr_id, reference, task.cpus, localmem)
    def csv_lines = ["library_id,fragments,cells"]
    def frag_list = fragments instanceof List ? fragments : [fragments]
    def cell_list = cells instanceof List ? cells : [cells]
    dataset_ids.eachWithIndex { did, i -> csv_lines << "${did},${frag_list[i]},${cell_list[i]}" }
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

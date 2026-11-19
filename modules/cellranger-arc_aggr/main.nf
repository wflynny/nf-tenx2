nextflow.enable.types = true

include { calc_localmem } from "../utils"

process CELLRANGER_ARC_AGGR {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger-arc/${version}" }

    input:
        tuple(aggr_id: String, version: String, reference: String, dataset_ids: List<String>,
              atac_frags: List<Path>, pbm: List<Path>, gex_mol: List<Path>)

    stage:
        stageAs atac_frags, '?_atac_fragments.tsv.gz'
        stageAs pbm, '?_per_barcode_metrics.csv'
        stageAs gex_mol, '?_gex_molecule_info.h5'

    output:
        results = tuple(aggr_id, file("cellranger-arc-aggr"))

    script:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson([pipeline: [dataset_id: aggr_id, tool_version: version], reference: reference])
    def csv_content = (['library_id,atac_fragments,per_barcode_metrics,gex_molecule_info'] + [dataset_ids, atac_frags, pbm, gex_mol].transpose().collect { row -> row.join(',') }).join('\\n')
    """
    printf '${csv_content}\\n' > aggr.csv

    run_10x.py --tool cellranger-arc-aggr --cpus ${task.cpus} --mem ${localmem} <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

    mkdir -p cellranger-arc-aggr/_files
    mv ${aggr_id}/_* cellranger-arc-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-arc-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-arc-aggr/
    """

    stub:
    def localmem = calc_localmem(task.memory)
    def rec_json = groovy.json.JsonOutput.toJson([pipeline: [dataset_id: aggr_id, tool_version: version], reference: reference])
    """
    run_10x.py --tool cellranger-arc-aggr --cpus ${task.cpus} --mem ${localmem} --dry-run <<- 'HEREDOC'
    ${rec_json}
    HEREDOC

    mkdir -p cellranger-arc-aggr/_files
    touch cellranger-arc-aggr/web_summary.html
    """
}

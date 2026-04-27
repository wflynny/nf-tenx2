include { calc_localmem } from "../utils"

process CELLRANGER_ARC_AGGR {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger-arc/${version}" }

    input:
        tuple val(aggr_id), val(version), val(reference), val(dataset_ids),
              path(atac_frags, stageAs: '?_atac_fragments.tsv.gz'),
              path(pbm, stageAs: '?_per_barcode_metrics.csv'),
              path(gex_mol, stageAs: '?_gex_molecule_info.h5')

    output:
        tuple val(aggr_id), path("cellranger-arc-aggr"),                        emit: results
        tuple val(aggr_id), path("cellranger-arc-aggr/collected_metrics.json"), emit: metrics

    script:
    def localmem = calc_localmem(task.memory)
    def cmd      = CommandBuilder.cellrangerArcAggr(aggr_id, reference, task.cpus, localmem)
    def csv_lines = ["library_id,atac_fragments,per_barcode_metrics,gex_molecule_info"]
    def frag_list = atac_frags instanceof List ? atac_frags : [atac_frags]
    def pbm_list  = pbm instanceof List ? pbm : [pbm]
    def mol_list  = gex_mol instanceof List ? gex_mol : [gex_mol]
    dataset_ids.eachWithIndex { did, i -> csv_lines << "${did},${frag_list[i]},${pbm_list[i]},${mol_list[i]}" }
    def csv_content = csv_lines.join('\\n')
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p cellranger-arc-aggr/_files
    mv ${aggr_id}/_* cellranger-arc-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-arc-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-arc-aggr/

    collect_metrics.py \\
        --pipestance-dir ${aggr_id} \\
        --tool-dir cellranger-arc-aggr \\
        --out cellranger-arc-aggr/collected_metrics.json
    """

    stub:
    """
    mkdir -p cellranger-arc-aggr/_files
    touch cellranger-arc-aggr/web_summary.html
    echo '{"aggregated":true}' > cellranger-arc-aggr/collected_metrics.json
    """
}

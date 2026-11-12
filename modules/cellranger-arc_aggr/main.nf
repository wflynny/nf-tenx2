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
    def cmd      = CommandBuilder.cellrangerArcAggr(aggr_id, reference, task.cpus, localmem)
    def csv_content = CommandBuilder.cellrangerArcAggrCsv(dataset_ids, atac_frags, pbm, gex_mol)
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p cellranger-arc-aggr/_files
    mv ${aggr_id}/_* cellranger-arc-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-arc-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-arc-aggr/
    """

    stub:
    """
    mkdir -p cellranger-arc-aggr/_files
    touch cellranger-arc-aggr/web_summary.html
    """
}

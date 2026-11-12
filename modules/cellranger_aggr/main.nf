nextflow.enable.types = true

include { calc_localmem } from "../utils"

/*
 * Aggregate multiple cellranger count/multi results.
 *
 * Input: grouped tuple of (aggr_id, version, dataset_ids, molecule_info.h5 files)
 * The molecule_info.h5 files are staged as 1_molecule_info.h5, 2_..., etc. to
 * avoid name collisions. The aggr CSV maps dataset_id → staged file path; the
 * dataset_ids and mol_h5s lists are positionally aligned, so List<Path>
 * (order-preserving) is required, not Set<Path>.
 */
process CELLRANGER_AGGR {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger/${version}" }

    input:
        tuple(aggr_id: String, version: String, dataset_ids: List<String>, mol_h5s: List<Path>)

    stage:
        stageAs mol_h5s, '?_molecule_info.h5'

    output:
        results = tuple(aggr_id, file("cellranger-aggr"))

    script:
    def localmem = calc_localmem(task.memory)
    def cmd      = CommandBuilder.cellrangerAggr(aggr_id, task.cpus, localmem)
    def csv_content = CommandBuilder.cellrangerAggrCsv(dataset_ids, mol_h5s)
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p cellranger-aggr/_files
    mv ${aggr_id}/_* cellranger-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-aggr/
    """

    stub:
    """
    mkdir -p cellranger-aggr/_files
    mkdir -p cellranger-aggr/analysis
    mkdir -p cellranger-aggr/count
    touch cellranger-aggr/web_summary.html
    touch cellranger-aggr/count/filtered_feature_bc_matrix.h5
    """
}

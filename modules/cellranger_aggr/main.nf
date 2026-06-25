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
        metrics = tuple(aggr_id, file("cellranger-aggr/collected_metrics.json"))

    script:
    def localmem = calc_localmem(task.memory)
    def cmd      = CommandBuilder.cellrangerAggr(aggr_id, task.cpus, localmem)
    // Build aggr CSV mapping dataset_ids to staged molecule_info files
    def csv_lines = ["sample_id,molecule_h5"]
    dataset_ids.eachWithIndex { did, i -> csv_lines << "${did},${mol_h5s[i]}" }
    def csv_content = csv_lines.join('\\n')
    """
    printf '${csv_content}\\n' > aggr.csv

    ${cmd}

    mkdir -p cellranger-aggr/_files
    mv ${aggr_id}/_* cellranger-aggr/_files/ || true
    mv ${aggr_id}/*.tgz cellranger-aggr/ || true
    mv ${aggr_id}/outs/* cellranger-aggr/

    collect_metrics.py \\
        --pipestance-dir ${aggr_id} \\
        --tool-dir cellranger-aggr \\
        --out cellranger-aggr/collected_metrics.json
    """

    stub:
    """
    mkdir -p cellranger-aggr/_files
    mkdir -p cellranger-aggr/analysis
    mkdir -p cellranger-aggr/count
    touch cellranger-aggr/web_summary.html
    touch cellranger-aggr/count/filtered_feature_bc_matrix.h5
    echo '{"aggregated":true}' > cellranger-aggr/collected_metrics.json
    """
}

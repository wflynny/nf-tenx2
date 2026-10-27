nextflow.enable.types = true

include { calc_localmem } from "../utils"
include { TenxNGSRecord } from "../types"

process CELLRANGER_ARC_COUNT {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger-arc/${record.pipeline.tool_version}" }

    input:
        tuple(record: TenxNGSRecord, libraries_csv: Path)

    stage:
        stageAs libraries_csv, 'libraries.csv'

    output:
        results = tuple(record, file("cellranger-arc"))
        metrics = tuple(record, file("cellranger-arc/collected_metrics.json"))

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def cmd        = CommandBuilder.cellrangerArcCount(record.raw, task.cpus, localmem)
    """
    ${cmd}

    mkdir -p cellranger-arc/_files
    mv libraries.csv cellranger-arc/
    mv ${dataset_id}/_* cellranger-arc/_files/ || true
    mv ${dataset_id}/*.tgz cellranger-arc/ || true
    mv ${dataset_id}/outs/* cellranger-arc/

    collect_metrics.py \\
        --pipestance-dir ${dataset_id} \\
        --tool-dir cellranger-arc \\
        --out cellranger-arc/collected_metrics.json
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    """
    mkdir -p cellranger-arc/_files
    mkdir -p cellranger-arc/filtered_feature_bc_matrix

    cp libraries.csv cellranger-arc/

    touch cellranger-arc/${dataset_id}.mri.tgz
    touch cellranger-arc/web_summary.html
    touch cellranger-arc/atac_fragments.tsv.gz
    touch cellranger-arc/atac_fragments.tsv.gz.tbi
    touch cellranger-arc/per_barcode_metrics.csv
    echo 'metric,value' > cellranger-arc/summary.csv
    echo 'Estimated number of cells,8000' >> cellranger-arc/summary.csv
    echo '{"summary.csv":{"metric":"Estimated number of cells","value":"8000"}}' > cellranger-arc/collected_metrics.json
    """
}

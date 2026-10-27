nextflow.enable.types = true

include { calc_localmem } from "../utils"
include { TenxNGSRecord    } from "../types"

process CELLRANGER_MULTI {

    label 'process_high'

    module { task.executor == 'local' ? '' : "cellranger/${record.pipeline.tool_version}" }

    input:
        tuple(record: TenxNGSRecord, multi_csv: Path)

    stage:
        stageAs multi_csv, 'multi.csv'

    output:
        results = tuple(record, file("cellranger-multi"))
        metrics = tuple(record, file("cellranger-multi/collected_metrics.json"))

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def cmd        = CommandBuilder.cellrangerMulti(record.raw, task.cpus, localmem)
    """
    ${cmd}

    mkdir -p cellranger-multi/_files
    mv multi.csv cellranger-multi/
    mv ${dataset_id}/_* cellranger-multi/_files/ || true
    mv ${dataset_id}/*.tgz cellranger-multi/ || true
    mv ${dataset_id}/outs/* cellranger-multi/

    collect_metrics.py \\
        --pipestance-dir ${dataset_id} \\
        --tool-dir cellranger-multi \\
        --out cellranger-multi/collected_metrics.json
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    def sample_ids = record.samples != null ? record.samples.collect { s -> s.sample_id ?: 'sample1' } : ['sample1']
    def mkdir_cmds = sample_ids.collect { sid ->
        """
        mkdir -p cellranger-multi/per_sample_outs/${sid}
        echo 'Estimated Number of Cells,Mean Reads per Cell' > cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        echo '3000,40000' >> cellranger-multi/per_sample_outs/${sid}/metrics_summary.csv
        touch cellranger-multi/per_sample_outs/${sid}/web_summary.html
        """
    }.join('\n')
    """
    mkdir -p cellranger-multi/_files
    mkdir -p cellranger-multi/multi/count/raw_feature_bc_matrix
    mkdir -p cellranger-multi/multi/count/filtered_feature_bc_matrix

    cp multi.csv cellranger-multi/

    touch cellranger-multi/${dataset_id}.mri.tgz
    touch cellranger-multi/multi/count/raw_feature_bc_matrix/barcodes.tsv.gz
    touch cellranger-multi/multi/count/filtered_feature_bc_matrix/barcodes.tsv.gz

    ${mkdir_cmds}

    echo '{"per_sample_outs/sample1/metrics_summary.csv":{"Estimated Number of Cells":"3000","Mean Reads per Cell":"40000"}}' > cellranger-multi/collected_metrics.json
    """
}

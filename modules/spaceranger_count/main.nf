nextflow.enable.types = true

include { calc_localmem } from "../utils"
include { TenxNGSRecord } from "../types"

process SPACERANGER_COUNT {

    label 'process_high'

    module { task.executor == 'local' ? '' : "spaceranger/${record.pipeline.tool_version}" }

    input:
        tuple(record: TenxNGSRecord, libraries_csv: Path)

    stage:
        stageAs libraries_csv, 'libraries.csv'

    output:
        results = tuple(record, file("spaceranger"))
        metrics = tuple(record, file("spaceranger/collected_metrics.json"))

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def cmd        = CommandBuilder.spacerangerCount(record.raw, task.cpus, localmem)
    """
    ${cmd}

    mkdir -p spaceranger/_files
    mv ${dataset_id}/_* spaceranger/_files/ || true
    mv ${dataset_id}/*.tgz spaceranger/ || true
    mv ${dataset_id}/outs/* spaceranger/

    collect_metrics.py \\
        --pipestance-dir ${dataset_id} \\
        --tool-dir spaceranger \\
        --out spaceranger/collected_metrics.json
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    """
    mkdir -p spaceranger/_files
    mkdir -p spaceranger/spatial
    mkdir -p spaceranger/filtered_feature_bc_matrix

    touch spaceranger/${dataset_id}.mri.tgz
    touch spaceranger/web_summary.html
    touch spaceranger/cloupe.cloupe
    touch spaceranger/spatial/tissue_positions.csv
    touch spaceranger/spatial/scalefactors_json.json
    echo 'Estimated Number of Spots Under Tissue,Mean Reads per Spot' > spaceranger/metrics_summary.csv
    echo '3500,60000' >> spaceranger/metrics_summary.csv
    echo '{"metrics_summary.csv":{"Estimated Number of Spots Under Tissue":"3500","Mean Reads per Spot":"60000"}}' > spaceranger/collected_metrics.json
    """
}

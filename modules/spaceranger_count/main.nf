include { calc_localmem } from "../utils"

process SPACERANGER_COUNT {

    label 'process_high'

    module { task.executor == 'local' ? '' : "spaceranger/${record.pipeline.tool_version}" }

    input:
        tuple val(record), path("libraries.csv")

    output:
        tuple val(record), path("spaceranger"),                       emit: results
        tuple val(record), path("spaceranger/metrics_summary.csv"),   emit: metrics

    script:
    def localmem   = calc_localmem(task.memory)
    def dataset_id = record.pipeline.dataset_id
    def cmd        = CommandBuilder.spacerangerCount(record, task.cpus, localmem)
    """
    ${cmd}

    mkdir -p spaceranger/_files
    mv ${dataset_id}/_* spaceranger/_files/ || true
    mv ${dataset_id}/*.tgz spaceranger/ || true
    mv ${dataset_id}/outs/* spaceranger/
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
    """
}

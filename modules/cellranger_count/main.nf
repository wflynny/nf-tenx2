include { strip_comment; record_get; calc_localmem } from "../utils"

process CELLRANGER_COUNT {

    label 'process_high'

    module "cellranger/${record.pipeline.tool_version}"

    input:
        tuple val(record), path("libraries.csv")

    output:
        tuple val(record), path("cellranger/**"),                    emit: results
        tuple val(record), path("cellranger/metrics_summary.csv"),   emit: metrics

    script:
    def localmem        = calc_localmem(task.memory)
    def dataset_id      = record.pipeline.dataset_id
    def reference       = record["gene-expression"].reference
    def create_bam      = strip_comment(record_get(record, "gene-expression", "create-bam", "false"))
    def include_introns = strip_comment(record_get(record, "gene-expression", "include-introns", "true"))
    """
    cellranger count \\
        --id ${dataset_id} \\
        --transcriptome ${reference} \\
        --create-bam ${create_bam} \\
        --include-introns ${include_introns} \\
        --libraries libraries.csv \\
        --localcores ${task.cpus} \\
        --localmem ${localmem} \\
        --disable-ui

    mkdir -p cellranger/_files
    mv libraries.csv cellranger/
    mv ${dataset_id}/_* cellranger/_files/ || true
    mv ${dataset_id}/*.tgz cellranger/ || true
    mv ${dataset_id}/outs/* cellranger/
    """

    stub:
    def dataset_id = record.pipeline.dataset_id
    """
    mkdir -p cellranger/_files
    mkdir -p cellranger/filtered_feature_bc_matrix
    mkdir -p cellranger/raw_feature_bc_matrix
    mkdir -p cellranger/analysis

    cp libraries.csv cellranger/

    touch cellranger/${dataset_id}.mri.tgz
    touch cellranger/web_summary.html
    touch cellranger/metrics_summary.csv
    touch cellranger/molecule_info.h5
    touch cellranger/filtered_feature_bc_matrix/barcodes.tsv.gz
    touch cellranger/filtered_feature_bc_matrix/features.tsv.gz
    touch cellranger/filtered_feature_bc_matrix/matrix.mtx.gz
    touch cellranger/raw_feature_bc_matrix/barcodes.tsv.gz
    touch cellranger/raw_feature_bc_matrix/features.tsv.gz
    touch cellranger/raw_feature_bc_matrix/matrix.mtx.gz
    touch cellranger/cloupe.cloupe

    echo '{"summary":{}}' > cellranger/summary.json
    echo 'Estimated Number of Cells,Mean Reads per Cell' > cellranger/metrics_summary.csv
    echo '5000,50000' >> cellranger/metrics_summary.csv
    """
}

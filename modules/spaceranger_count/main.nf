process SPACERANGER_COUNT {
    publishDir "${params.pubdir}/${record.pipeline.dataset_id}", mode: 'copy'

    label 'process_high'

    module { "spaceranger/${record.pipeline.tool_version}" }

    input:
        tuple val(record), path("libraries.csv")

    output:
        tuple val(record), path("spaceranger/**"),                    emit: results
        tuple val(record), path("spaceranger/metrics_summary.csv"),   emit: metrics

    script:
    def localmem   = Math.round(task.memory.toGiga() * 0.95)
    def dataset_id = record.pipeline.dataset_id
    def reference  = record["gene-expression"].reference
    def fastq_dirs = record.libraries.collect { it.fastqs }.unique().join(',')
    def samples    = record.libraries.collect { it.sample }.unique().join(',')
    // spaceranger requires slide/area info
    def slide      = record.containsKey('spatial') ? record.spatial.slide ?: '' : ''
    def area       = record.containsKey('spatial') ? record.spatial.area ?: '' : ''
    def image      = record.containsKey('spatial') ? record.spatial.image ?: '' : ''
    """
    spaceranger count \\
        --id ${dataset_id} \\
        --transcriptome ${reference} \\
        --fastqs ${fastq_dirs} \\
        --sample ${samples} \\
        ${slide ? "--slide ${slide}" : ''} \\
        ${area ? "--area ${area}" : ''} \\
        ${image ? "--image ${image}" : ''} \\
        --localcores ${task.cpus} \\
        --localmem ${localmem} \\
        --disable-ui

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
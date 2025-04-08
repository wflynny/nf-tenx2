process GENERATE_GEX_METADATA {
    input:
        tuple val(record), path("hashes.*")
    output:
        path("pipeline-metadata.json")
    
    script:
    """
    """
}
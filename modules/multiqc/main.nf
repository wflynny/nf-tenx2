process MULTIQC {
    input:
        tuple val(record), path("*")
    output:
        path("*")
    script:    
    """
    multiqc .
    """ 

    stub:
    """
    touch multiqc.html
    """
}
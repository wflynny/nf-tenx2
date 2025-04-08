process MD5SUM {
    input:
        tuple val(record), path("*")
    output:
        tuple val(record), path("*.md5"), emit: hashes
    script:
    """
    md5sum * > hashes.md5
    """

    stub:
    """
    touch hashes.md5
    """
}

process SHA1SUM {
    input:
        tuple val(record), path("*")
    output:
        tuple val(record), path("*.sha1"), emit: hashes
    script:
    """
    sha1sum * > hashes.sha1
    """ 

    stub:
    """
    touch hashes.md5
    """
}
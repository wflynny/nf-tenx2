process MD5SUM {
    input:
        tuple val(record), path(files, stageAs: 'to_hash/*')
    output:
        tuple val(record), path("hashes.md5"), emit: hashes
    script:
    """
    find to_hash/ -type f | sort | xargs md5sum > hashes.md5
    """

    stub:
    """
    touch hashes.md5
    """
}

process SHA1SUM {
    input:
        tuple val(record), path(files, stageAs: 'to_hash/*')
    output:
        tuple val(record), path("hashes.sha1"), emit: hashes
    script:
    """
    find to_hash/ -type f | sort | xargs sha1sum > hashes.sha1
    """ 

    stub:
    """
    touch hashes.sha1
    """
}

process SHA256SUM {
    label 'process_single'

    input:
        tuple val(record), path(files, stageAs: 'to_hash/*')

    output:
        tuple val(record), path("hashes.sha256"), emit: hashes

    script:
    """
    find to_hash/ -type f | sort | xargs sha256sum > hashes.sha256
    """

    stub:
    """
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  stub_file" > hashes.sha256
    """
}

process MD5SUM {
    label 'process_single'

    input:
        tuple val(record), path(result_dir)
    output:
        tuple val(record), path("hashes.md5"), emit: hashes
    script:
    """
    find -L ${result_dir} -type f -not -name '.*' | sort | while read -r f; do
        md5sum "\$f"
    done > hashes.md5
    """

    stub:
    """
    echo "d41d8cd98f00b204e9800998ecf8427e stub_file" > hashes.md5
    """
}

process SHA1SUM {
    input:
        tuple val(record), path(result_dir)
    output:
        tuple val(record), path("hashes.sha1"), emit: hashes
    script:
    """
    find ${result_dir} -type f | sort | while read -r f; do
        sha1sum "\$f"
    done > hashes.sha1
    """

    stub:
    """
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  stub_file" > hashes.sha1
    """
}

process SHA256SUM {
    label 'process_single'

    input:
        tuple val(record), path(result_dir)

    output:
        tuple val(record), path("hashes.sha256"), emit: hashes

    script:
    """
    find ${result_dir} -type f | sort | while read -r f; do
        sha256sum "\$f"
    done > hashes.sha256
    """

    stub:
    """
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  stub_file" > hashes.sha256
    """
}

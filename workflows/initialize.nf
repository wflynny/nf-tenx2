workflow INITIALIZE {
    take:
        version

    main:
        ch_versions = Channel.empty()

        print_header(version)

    emit:
        versions = ch_versions
}

def print_header(version) {
    println version
}

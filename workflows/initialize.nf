def print_header(version, pipeline, inputDir, pubdir) {
    log.info """
    ╔═══════════════════════════════════════╗
    ║           nf-tenx2 v${version}            ║
    ║   10x Genomics Processing Pipeline    ║
    ╚═══════════════════════════════════════╝

    Pipeline  : ${pipeline ?: 'not set'}
    Input dir : ${inputDir ?: 'not set'}
    Output dir: ${pubdir}
    Profile   : ${workflow.profile}
    ─────────────────────────────────────────
    """.stripIndent()
}

workflow INITIALIZE {
    take:
        version
        pipeline
        inputJsonFiles
        inputDir
        pubdir

    main:
        print_header(version, pipeline, inputDir, pubdir)

        if (!pipeline) {
            error "Parameter --pipeline is required"
        }
        if (!inputJsonFiles && !inputDir) {
            error "Provide input via --input-json-files or --input-dir"
        }
}

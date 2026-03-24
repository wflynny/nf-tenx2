def print_header(version) {
    log.info """
    ╔═══════════════════════════════════════╗
    ║           nf-tenx2 v${version}        ║
    ║   10x Genomics Processing Pipeline    ║
    ╚═══════════════════════════════════════╝

    Pipeline  : ${params.pipeline ?: 'not set'}
    Input dir : ${params.inputDir ?: 'not set'}
    Output dir: ${params.pubdir}
    Profile   : ${workflow.profile}
    ─────────────────────────────────────────
    """.stripIndent()
}

workflow INITIALIZE {
    take:
        version

    main:
        print_header(version)

        // Validate required params
        if (!params.pipeline) {
            error "Parameter --pipeline is required"
        }
        if (!params.inputJsonFiles && !params.inputDir) {
            error "Provide input via --input-json-files or --input-dir"
        }
}

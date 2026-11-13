def print_header(version, pipeline, inputDir, pubdir) {
    log.info """
    ==========================================
      nf-tenx2 v${version}
      10x Genomics Processing Pipeline
    ==========================================
    Pipeline  : ${pipeline}
    Input dir : ${inputDir}
    Output dir: ${pubdir}
    Profile   : ${workflow.profile}
    ------------------------------------------
    """.stripIndent()
}

workflow INITIALIZE {
    take:
        version
        pipeline
        inputDir
        pubdir

    main:
        print_header(version, pipeline, inputDir, pubdir)
}

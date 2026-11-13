/*
 * Real (non-stub) run of RESOLVE_FASTQS on a fake core delivery. Stub runs never
 * execute its script, and the script decides which FASTQs a client receives.
 *
 * Checks: the match is anchored (Lib10 and Lib1_Sample2 are not Lib1), and a
 * top-up run lands in its own fastq/<source dir>/ next to the first run.
 *
 * Run: nextflow run test/resolve_fastqs.nf -c nextflow.config -profile testing
 */

include { RESOLVE_FASTQS } from "../modules/resolve_fastqs"

workflow {
    def core = workflow.workDir.resolve('resolve-fastqs-fixture')
    def run1 = core.resolve('20261109_GT26-Test-338')
    def run2 = core.resolve('20261120_GT26-Test-338-run2')
    run1.mkdirs()
    run2.mkdirs()
    ['Lib1_S1_L001_R1_001', 'Lib1_S1_L001_R2_001', 'Lib10_S2_L001_R1_001', 'Lib1_Sample2_S3_L001_R1_001'].each { n ->
        run1.resolve("${n}.fastq.gz").text = "run1 ${n}"
    }
    run2.resolve('Lib1_S1_L001_R1_001.fastq.gz').text = 'run2'

    def rec = [pipeline: [dataset_id: 'ResolveTest'],
               libraries: [[fastq_id: 'Lib1', fastqs: run1.toString()], [fastq_id: 'Lib1', fastqs: "${run2}/"]]]
    def expected = [
        '20261109_GT26-Test-338/Lib1_S1_L001_R1_001.fastq.gz',
        '20261109_GT26-Test-338/Lib1_S1_L001_R2_001.fastq.gz',
        '20261120_GT26-Test-338-run2/Lib1_S1_L001_R1_001.fastq.gz',
    ]

    RESOLVE_FASTQS(channel.of(rec))
    RESOLVE_FASTQS.out.fastq.subscribe { _rec, fq_dir ->
        def got = files("${fq_dir}/**.fastq.gz").collect { f -> fq_dir.relativize(f).toString() }.sort()
        assert got == expected : "RESOLVE_FASTQS resolved ${got}, expected ${expected}"
        println "resolve_fastqs: OK"
    }
}

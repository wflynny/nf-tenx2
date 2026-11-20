nextflow.enable.types = true

/*
 * Check all input JSONs with bin/validate_records.py before any job starts.
 * Runs on the head node: it takes seconds and should not wait in the queue.
 * No stub block, so -stub runs the real check too. Never cached, so every
 * launch (including -resume) re-checks the inputs against the current rules.
 */
process VALIDATE_RECORDS {
    executor 'local'
    cache false
    label 'process_single'

    input:
        pipeline: String
        jsons: List<Path>

    output:
        stdout()

    script:
    """
    validate_records.py --pipeline ${pipeline} *.json
    """
}

/*
 * Utility functions for input collection and record manipulation.
 */

def collect_input_json_files(inputJsonFiles, inputDir) {
    def files = []
    if (inputJsonFiles) {
        if (inputJsonFiles instanceof List) {
            inputJsonFiles.each { f -> files.add(file(f)) }
        } else {
            files.add(file(inputJsonFiles))
        }
    }

    if (inputDir) {
        file("${inputDir}/**.json").each { f -> files.add(f) }
    }

    if (files.size() == 0) {
        error "No input JSON files found. Supply --input-json-files or --input-dir"
    }

    return files.unique(false)
}

/**
 * Extract all FASTQ directory paths from a parsed JSON record.
 * Returns a list of unique path strings.
 */
def extract_fastq_paths(record) {
    def paths = []
    if (record.containsKey('libraries') && record.libraries instanceof List) {
        record.libraries.each { lib ->
            if (lib.fastqs) {
                paths.add(lib.fastqs)
            }
        }
    }
    return paths.unique()
}

/**
 * Extract unique sample name prefixes from a record's libraries.
 * These prefixes are used to filter FASTQs to only those belonging to this dataset.
 * Returns a list of unique sample name strings.
 */
def extract_sample_prefixes(record) {
    def prefixes = []
    def libs = record?.libraries
    if (libs instanceof List) {
        libs.each { lib ->
            if (lib?.sample) {
                prefixes.add(lib.sample)
            }
        }
    }
    return prefixes.unique()
}

/**
 * Determine whether a GEX record should use cellranger multi vs cellranger count.
 * Multi is triggered by the presence of a 'samples' section.
 */
def is_multi_record(record) {
    return record.containsKey('samples')
}

/**
 * Get a safe value from a nested record map, returning a default if the key
 * doesn't exist or is empty.
 */
def record_get(record, section, key, defaultValue) {
    if (!record.containsKey(section)) return defaultValue
    def sec = record[section]
    if (sec instanceof Map && sec.containsKey(key)) {
        def val = sec[key]
        if (val == null || val.toString().trim() == '') return defaultValue
        return val
    }
    return defaultValue
}

/**
 * Strip inline comments from a record value
 * e.g. "false #do not generate BAM file" -> "false"
 */
def strip_comment(value) {
    if (value == null) return null
    return value.toString().split('#')[0].trim()
}

/**
 * Calculate --localmem value for 10x tools from task.memory.
 * Returns 95% of available memory in GB, with a fallback default
 * if task.memory is null (e.g. no profile loaded).
 */
def calc_localmem(task_memory, fallback_gb = 64) {
    if (task_memory == null) return fallback_gb
    return Math.round(task_memory.toGiga() * 0.95)
}

/**
 * Build a JSON string capturing Nextflow workflow provenance.
 * Called in workflow blocks where the workflow object is accessible.
 */
def capture_workflow_json(pipeline_version) {
    def wf_info = [
        pipeline_name:    "nf-tenx2",
        pipeline_version: pipeline_version,
        nextflow_version: nextflow.version.toString(),
        profile:          workflow.profile.toString(),
        command_line:      workflow.commandLine.toString(),
        run_name:          workflow.runName.toString(),
        session_id:        workflow.sessionId.toString(),
        start:             workflow.start.toString(),
        script_id:         workflow.scriptId.toString(),
        work_dir:          workflow.workDir.toString(),
        launch_dir:        workflow.launchDir.toString(),
        user_name:         workflow.userName.toString(),
    ]
    return groovy.json.JsonOutput.prettyPrint(
        groovy.json.JsonOutput.toJson(wf_info)
    )
}

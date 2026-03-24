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

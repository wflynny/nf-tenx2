/*
 * Utility functions for input collection and record manipulation.
 */

def collect_input_json_files() {
    def files = []
    if (params.inputJsonFiles) {
        // handle both single file and list of files
        if (params.inputJsonFiles instanceof List) {
            params.inputJsonFiles.each { files << file(it) }
        } else {
            files << file(params.inputJsonFiles)
        }
    }

    if (params.inputDir) {
        files += file("${params.inputDir}/**.json")
    }

    if (files.size() == 0) {
        error "No input JSON files found. Supply --input-json-files or --input-dir"
    }

    return files.unique(false)
}

/**
 * Extract all FASTQ directory paths from a parsed JSON record.
 * Works for both 'libraries' (count-style) and sectioned multi-style records.
 * Returns a list of unique path strings.
 */
def extract_fastq_paths(record) {
    def paths = []
    if (record.containsKey('libraries') && record.libraries instanceof List) {
        record.libraries.each { lib ->
            if (lib.fastqs) {
                paths << lib.fastqs
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
def record_get(record, String section, String key, defaultValue) {
    if (!record.containsKey(section)) return defaultValue
    def sec = record[section]
    if (sec instanceof Map && sec.containsKey(key)) {
        def val = sec[key]
        // handle empty strings and comment-appended values
        if (val == null || val.toString().trim() == '') return defaultValue
        return val
    }
    return defaultValue
}

/**
 * Strip inline comments from a record value (e.g. "false #do not generate BAM file" -> "false")
 */
def strip_comment(value) {
    if (value == null) return null
    return value.toString().split('#')[0].trim()
}

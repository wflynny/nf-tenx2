def collect_input_csvs() {
    files = []
    if (params.inputCsvs) {
        files += file(params.inputCsvs)
    }

    if (params.inputDir) {
        files += file("${params.inputDir}/**.csv")
    }

    return files.unique(false)

}

def collect_input_json_files() {
    files = []
    if (params.inputJsonFiles) {
        files += file(params.inputJsonFiles)
    }

    if (params.inputDir) {
        files += file("${params.inputDir}/**.json")
    }

    return files.unique(false)
}
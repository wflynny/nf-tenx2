def collect_input_csvs() {
    def files = []
    if (params.inputCsvs) {
        files += file(params.inputCsvs)
    }

    if (params.inputDir) {
        files += file("${params.inputDir}/**.csv")
    }

    return files.unique(false)

}

def collect_input_json_files() {
    def files = []
    if (params.inputJsonFiles) {
        files += file(params.inputJsonFiles)
    }

    if (params.inputDir) {
        files += file("${params.inputDir}/**.json")
    }

    return files.unique(false)
}
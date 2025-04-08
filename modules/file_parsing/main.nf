/*
Why are we parsing csvs? The purpose of each csv file is a specification that
can be directly slurped by *ranger*.  However, if this pipeline supports
literally any other tools or processes--e.g. FASTQC, phenocycler-fusion,
xenium--those additional modules need access to things like FASTQ file locations

After some consideration, only a subset of the '*ranger' tools even support the
multi-config paradigm, and the 'libraries.csv' implementation is inaccurate as
any invocation using 'libraries.csv' also requires:
- --id
- --fastqs
- --samples
- --transcriptome
- --create-bam T/F

So instead, EVERY config will be specified using the 'multi.csv' config format so that
- all info needed to run is included in the csv
- once cellranger* rebrands the multi pipeline, we have preemptive compatibility
For those tools that don't support multi.csv, we will need to parse then convert

Here's the catch--the CSV format used by cellranger is nonstandard (e.g. not a
sectioned configobject) but instead a sectioned csv.  We can parse this and save
as a JSON file to be slurped by 

Definition of a record as returned here:
- 

*/


process RECORD_TO_JSON_FILE {
    input:
        val(record)
    
    output:
        tuple(val(record), file("rec.json"))
    
    exec:
    def jsonString = record.toJson()
    def jsonFile = new File("rec.json")
    jsonFile.text = jsonString
}

process JSON_TO_MULTI_CSV {
    input:
        tuple(val(record), file("rec.json"))
    
    output:
        tuple(val(record), file("multi.csv"))

    script:
    """
    cellranger_csv.py \
        --input-file rec.json \
        --output-type multi \
        --output-file multi.csv
    """
}

process JSON_TO_LIBRARIES_CSV {
    input:
        tuple(val(record), file("rec.json"))
    
    output:
        tuple(val(record), file("libraries.csv"))

    script:
    """
    cellranger_csv.py \
        --input-file rec.json \
        --output-type libraries \
        --unsectioned-output-key libraries \
        --output-file libraries.csv
    """
}

process LIBRARIES_CSV_TO_JSON {
    input:
        tuple(val(record), file("libraries.csv"))
    
    output:
        tuple(val(record), file("rec.json"))

    script:
    """
    cellranger_csv.py \
        --input-file libraries.csv \
        --unsectioned-input-key libraries \
        --output-type json \
        --output-file rec.json
    """
}

process MULTI_CSV_TO_JSON {
    input:
        tuple(val(record), file("multi.csv"))
    
    output:
        tuple(val(record), file("rec.json"))

    script:
    """
    cellranger_csv.py \
        --input-file multi.csv \
        --output-type json \
        --output-file rec.json
    """
}

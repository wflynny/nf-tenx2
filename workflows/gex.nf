/*
expectation is that:
- cellranger_count
    - 3' GEX
    - 3' GEX + AB
    - 3' AB only
    - 5' GEX
    - 5' GEX + AB
- cellranger_multi
    - 3' GEX + HTO
    - 3' GEX + HTO + AB
    - 5' GEX + VDJ
    - 5' GEX + VDJ + AB
    - 5' GEX + BEAM
- cellranger_vdj
    - vdj only
 
*/
nextflow.enable.dsl=2

include { CELLRANGER_MULTI } from "../modules/cellranger_multi"
include { CELLRANGER_COUNT } from "../modules/cellranger_count"
include { FASTQC } from "../modules/fastqc"
include { MULTIQC } from "../modules/multiqc"
include { MD5SUM } from "../modules/hash"
include { JSON_TO_MULTI_CSV; JSON_TO_LIBRARIES_CSV; RECORD_TO_JSON_FILE } from "../modules/file_parsing"


workflow MULTI {
    take:
    records
    
    main:
    records | RECORD_TO_JSON_FILE | JSON_TO_MULTI_CSV
}

workflow COUNT {
    take:
    records
    
    main:
    records | RECORD_TO_JSON_FILE | JSON_TO_LIBRARIES_CSV
}

workflow GEX {
    take:
    records

    main:
    // for every record, generate input file
    // pass multi to cellranger multi
    // pass count to cellranger count
    // fastqs go to FASTQC
    // FASTQC results go to MULTIQC
    records
        .branch { 
            multi: it.containsKey("gene-expression") 
            count: true
        }
        .set { cellranger }

    results_multiqc = FASTQC(records) | MULTIQC(records) | MD5SUM

    results_cellranger = CELLRANGER_MULTI(MULTI(cellranger.multi)).join(
        CELLRANGER_COUNT(COUNT(cellranger.count)), remainder: true
    ) | MD5SUM
    

    


}
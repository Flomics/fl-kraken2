#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Flomics/fl-kraken2
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Download → Trim → Kraken2 + Krona phylogenetic classification pipeline.

    Input: two-column TSV (tab-separated, no header):
      <accession_id>  <dataset_batch>

    Supported accession types:
      SRR<d>           — plain ENA/SRA (fastq-dl)
      SRRISOLATE_<d>   — multi-run merge via SraRunTable.csv
      X<d>             — BioSample merge via runs_to_biosamples.csv
      SAMP<d>*         — ENA FTP (PRJEB90290) via ena_prjeb90290.tsv
      RNA<d>_S<d>      — EGA download via pyega3

    Usage:
      nextflow run /path/to/fl-kraken2 \
        --input  samples.tsv \
        --outdir results \
        -profile docker
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PRINT LOGO
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

log.info NfcoreTemplate.logo(workflow, params.monochrome_logs)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE PARAMETERS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

if (!params.input) {
    error "Please provide an input TSV: --input samples.tsv"
}

if (!params.kraken2_db) {
    error "Please provide a Kraken2 database path: --kraken2_db /path/to/db"
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOW FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { PHYLO } from './workflows/phylo'

workflow {
    PHYLO ()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { DOWNLOAD_TRIM  } from '../subworkflows/local/download_trim.nf'
include { FLOMICS_PHYLO  } from '../subworkflows/local/flomics_phylo.nf'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Datasets that produce single-end FASTQ files
def SE_DATASETS = ~/(?i)(giraldez.*)/

workflow PHYLO {

    //
    // Parse two-column TSV (no header):
    //   <accession_id>  <dataset_batch>
    // Tab or space separated; lines starting with # are comments.
    //
    Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(sep: '\t', strip: true)
        .filter { row -> row.size() >= 2 && !row[0].startsWith('#') && row[0] }
        .map { row ->
            def accession = row[0].trim()
            def dataset   = row[1].trim()
            def meta = [
                id         : accession,
                single_end : (dataset ==~ SE_DATASETS),
                dataset    : dataset
            ]
            return [ meta, dataset ]
        }
        .set { ch_input }

    //
    // SUBWORKFLOW: Download + trim (download → umi_tools? → trim_galore)
    //
    DOWNLOAD_TRIM ( ch_input )

    //
    // SUBWORKFLOW: Kraken2 taxonomic classification + Krona visualisation
    //
    FLOMICS_PHYLO ( DOWNLOAD_TRIM.out.reads )
}

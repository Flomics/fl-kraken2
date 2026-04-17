//
// Download raw FASTQ files, optionally extract UMIs, then run Trim Galore.
// Mirrors the SLURM chain: download → (umi_tools extract) → trim_galore
//
// UMI extraction is performed only for datasets where it is required:
//   decruyenaere, flomics_1, flomics_2
// The dataset-specific Trim Galore args are set via ext.args in modules.config.
//

include { DOWNLOAD_SAMPLE  } from '../../modules/local/download_sample.nf'
include { UMITOOLS_EXTRACT } from '../../modules/local/umitools_extract.nf'
include { TRIMGALORE       } from '../../modules/local/trimgalore.nf'

// Datasets that require UMI extraction before trimming
def UMI_DATASETS = ~/(?i)(decruyenaere|flomics[_-]?[12]|flomics1|flomics2)/


workflow DOWNLOAD_TRIM {
    take:
    reads  // channel: [ val(meta), val(dataset) ]
           // meta must contain: id, single_end, dataset


    main:

    //
    // MODULE: Download raw FASTQ files
    //
    DOWNLOAD_SAMPLE (
        reads,
        params.sra_run_table      ? file(params.sra_run_table)      : [],
        params.isolate_to_runs    ? file(params.isolate_to_runs)    : [],
        params.ena_prjeb90290_tsv ? file(params.ena_prjeb90290_tsv) : [],
        params.ega_files_csv      ? file(params.ega_files_csv)      : [],
        params.ega_credentials    ? file(params.ega_credentials)    : []
    )

    // Reformat to [ meta, [r1, r2] ] for PE or [ meta, [r1] ] for SE
    ch_raw = DOWNLOAD_SAMPLE.out.reads
        .map { meta, r1, r2 -> [ meta, meta.single_end ? [ r1 ] : [ r1, r2 ] ] }

    //
    // Branch: UMI datasets need extraction before trimming; others go straight to trim
    //
    ch_raw.branch { meta, reads ->
        umi:    meta.dataset ==~ UMI_DATASETS
        no_umi: true
    }.set { ch_branched }

    //
    // MODULE: UMI extraction (UMI datasets only)
    //
    UMITOOLS_EXTRACT ( ch_branched.umi )

    //
    // Merge UMI-extracted and non-UMI reads back into a single channel for trimming
    //
    ch_for_trimming = UMITOOLS_EXTRACT.out.reads
        .mix( ch_branched.no_umi )

    //
    // MODULE: Trim Galore (dataset-specific args set via ext.args in modules.config)
    //
    TRIMGALORE ( ch_for_trimming )

    emit:
    reads   = TRIMGALORE.out.reads  // channel: [ val(meta), [ path(trimmed_reads) ] ]
    reports = TRIMGALORE.out.log
}

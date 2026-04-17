//
// Flomics Phylogenetic classification
// (downsampling step removed — runs on full input reads)
//

include { KRAKEN2              } from '../../modules/local/kraken2.nf'
include { KRONA_KTUPDATETAXONOMY } from '../../modules/nf-core/krona/ktupdatetaxonomy/main.nf'
include { KRONA_KTIMPORTTAXONOMY } from '../../modules/nf-core/krona/ktimporttaxonomy/main.nf'
include { UNTAR as UNTAR_KRAKEN2_DB } from '../../modules/nf-core/untar/main.nf'


workflow FLOMICS_PHYLO {
    take:
    reads // channel: [ val(meta), [ path(reads) ] ]


    main:

    //
    // MODULE: Untar kraken2_db if compressed
    //
    if (params.kraken2_db.endsWith('.gz')) {
        UNTAR_KRAKEN2_DB ( [ [:], params.kraken2_db ] )
        ch_kraken2_db = UNTAR_KRAKEN2_DB.out.untar.map { it[1] }
    } else {
        ch_kraken2_db = Channel.fromPath(params.kraken2_db, checkIfExists: true)
        ch_kraken2_db = ch_kraken2_db.collect()
    }

    //
    // MODULE: Perform Kraken2 taxonomic classification
    //
    ch_k2_filtered_report = Channel.empty()
    KRAKEN2 (
        reads,
        ch_kraken2_db
    )
    ch_k2_filtered_report = KRAKEN2.out.filtered_report
        .map { meta, full_report -> [ full_report ] }
        .collect()
        .ifEmpty([])

    //
    // MODULE: Update Krona taxonomy database
    //
    // KRONA_KTUPDATETAXONOMY ()

    // //
    // // MODULE: Create Krona plots from Kraken2 reports
    // //
    // ch_krona_input = KRAKEN2.out.report
    //     .map { meta, report -> report }
    //     .collect()
    //     .map { reports ->
    //         [
    //             [ id: 'multi-krona' ],
    //             reports
    //         ]
    //     }

    // KRONA_KTIMPORTTAXONOMY (
    //     ch_krona_input,
    //     KRONA_KTUPDATETAXONOMY.out.db
    // )

    emit:
    kraken2_report          = KRAKEN2.out.report.map { meta, report -> [ report ] }.collect()
    kraken2_filtered_report = ch_k2_filtered_report
    //krona_html              = KRONA_KTIMPORTTAXONOMY.out.html
}

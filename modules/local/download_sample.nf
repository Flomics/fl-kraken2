process DOWNLOAD_SAMPLE {
    tag "$meta.id"
    label 'process_download'

    conda "${moduleDir}/download_sample/environment.yml"

    input:
    tuple val(meta), val(dataset)
    path sra_run_table
    path isolate_to_runs
    path ena_prjeb90290_tsv
    path ega_files_csv
    path ega_credentials

    output:
    tuple val(meta), path("${meta.id}_1.fastq.gz"), path("${meta.id}_2.fastq.gz"), emit: reads

    script:
    def accession = meta.id
    """
    download_sample.sh \\
        "${accession}" \\
        "${dataset}" \\
        "${sra_run_table}" \\
        "${isolate_to_runs}" \\
        "${ena_prjeb90290_tsv}" \\
        "${ega_files_csv}" \\
        "${ega_credentials}"
    """
}

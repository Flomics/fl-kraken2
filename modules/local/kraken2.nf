process KRAKEN2 {
    tag "$meta.id"
    label 'process_high'

    conda "bioconda::kraken2=2.1.2"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/kraken2:2.1.2--pl5321h9f5acd7_3' :
        'quay.io/biocontainers/kraken2:2.1.2--pl5321h9f5acd7_3' }"

    input:
    tuple val(meta), path(reads)
    path(db)

    output:
    tuple val(meta), path("*kraken2.report.txt"), emit: report
    tuple val(meta), path("*filtered_report.tsv.gz"), optional: true, emit: filtered_report

    script:
    pe = meta.single_end ? "" : "--paired"
    if (params.phylo_kraken_full_report) {
        if (meta.single_end) {
            """
            kraken2 \\
                --db $db \\
                --threads $task.cpus \\
                --report ${meta.id}.kraken2.report.txt \\
                $pe \\
                --gzip-compressed \\
                $reads | gzip > ${meta.id}.kraken2.full_report.tsv.gz

            zcat ${meta.id}.kraken2.full_report.tsv.gz | awk -F'\t' 'BEGIN {print "#read_id\tNCBI_tax_id\tLCA_hitlist"} {print \$2"\t"\$3"\t"\$5}' | gzip > ${meta.id}.kraken2.filtered_report.tsv.gz
            """
        } else {
            """
            kraken2 \\
                --db $db \\
                --threads $task.cpus \\
                --report ${meta.id}.kraken2.report.txt \\
                $pe \\
                --gzip-compressed \\
                ${reads[0]} ${reads[1]} | gzip > ${meta.id}.kraken2.full_report.tsv.gz

            zcat ${meta.id}.kraken2.full_report.tsv.gz | awk -F'\t' 'BEGIN {print "#read_id\tNCBI_tax_id\tLCA_hitlist"} {print \$2"\t"\$3"\t"\$5}' | gzip > ${meta.id}.kraken2.filtered_report.tsv.gz
            """
        }
    } else {
        if (meta.single_end) {
            """
            kraken2 \\
                --db $db \\
                --threads $task.cpus \\
                --report ${meta.id}.kraken2.report.txt \\
                $pe \\
                --gzip-compressed \\
                $reads
            """
        } else {
            """
            kraken2 \\
                --db $db \\
                --threads $task.cpus \\
                --report ${meta.id}.kraken2.report.txt \\
                $pe \\
                --gzip-compressed \\
                ${reads[0]} ${reads[1]}
            """
        }
    }
}

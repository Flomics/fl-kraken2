process TRIMGALORE {
    tag "$meta.id"
    label 'process_medium'

    conda 'bioconda::trim-galore=0.6.7'
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/trim-galore:0.6.7--hdfd78af_0' :
        'quay.io/biocontainers/trim-galore:0.6.7--hdfd78af_0' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*{trimmed,val}*.fq.gz"), emit: reads
    tuple val(meta), path("*report.txt")           , emit: log
    tuple val(meta), path("*.html")                , emit: html, optional: true
    tuple val(meta), path("*.zip")                 , emit: zip,  optional: true

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args  ?: ''
    def args2  = task.ext.args2 ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    // TrimGalore recommends max 4 cores internally
    def cores = 1
    if (task.cpus) {
        cores = (task.cpus as int) - 4
        if (cores < 1) cores = 1
        if (cores > 4) cores = 4
    }
    if (meta.single_end) {
    """
    [ ! -f  ${prefix}.fastq.gz ] && ln -sf ${reads[0]} ${prefix}.fastq.gz
    trim_galore \\
        $args \\
        $args2 \\
        --cores $cores \\
        --gzip \\
        ${prefix}.fastq.gz
    """
    } else {
    """
    [ ! -f  ${prefix}_1.fastq.gz ] && ln -sf ${reads[0]} ${prefix}_1.fastq.gz
    [ ! -f  ${prefix}_2.fastq.gz ] && ln -sf ${reads[1]} ${prefix}_2.fastq.gz
    trim_galore \\
        $args \\
        $args2 \\
        --cores $cores \\
        --paired \\
        --gzip \\
        ${prefix}_1.fastq.gz \\
        ${prefix}_2.fastq.gz
    """
    }
}

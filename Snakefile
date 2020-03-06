"""General purpose RNA-Seq analysis pipeline developed by the Zavolan Lab"""

import os
import sys

import pandas as pd

# Get sample table
samples_table = pd.read_csv(
    config['samples'],
    header=0,
    index_col=0,
    comment='#',
    engine='python',
    sep="\t",
)

# Global config
localrules: finish

# Create log directories
os.makedirs(
    os.path.join(
        os.getcwd(),
        config['log_dir'],
    ),
    exist_ok=True)

if cluster_config:
    os.makedirs(
        os.path.join(
            os.getcwd(),
            os.path.dirname(cluster_config['__default__']['out']),
        ),
        exist_ok=True)

# Include subworkflows
include: os.path.join("workflow", "rules", "paired_end.snakefile.smk")
include: os.path.join("workflow", "rules", "single_end.snakefile.smk")

rule finish:
    """
        Rule for collecting outputs
    """
    input:
        outdir1 = expand(
            os.path.join(
                config['output_dir'],
                "{seqmode}",
                "{sample}",
                "mate1_fastqc"),
            zip,
            sample=[i for i in list(samples_table.index.values)],
            seqmode=[samples_table.loc[i, 'seqmode']
                     for i in list(samples_table.index.values)]),
        salmon_gn_estimates = expand(
            os.path.join(
                config['output_dir'],
                "{seqmode}",
                "{sample}",
                "salmon_quant",
                "quant.genes.sf"),
            zip,
            sample=[i for i in list(samples_table.index.values)],
            seqmode=[samples_table.loc[i, 'seqmode']
                     for i in list(samples_table.index.values)]),
        pseudoalignment = expand(
            os.path.join(
                config['output_dir'],
                "{seqmode}",
                "{sample}",
                "quant_kallisto",
                "{sample}.kallisto.pseudo.sam"),
            zip,
            sample=[i for i in list(samples_table.index.values)],
            seqmode=[samples_table.loc[i, 'seqmode']
                     for i in list(samples_table.index.values)]),
        TIN_score = expand(
            os.path.join(
                config['output_dir'],
                "{seqmode}",
                "{sample}",
                "TIN",
                "TIN_score.tsv"),
            zip,
            sample=[i for i in list(samples_table.index.values)],
            seqmode=[samples_table.loc[i, 'seqmode']
                     for i in list(samples_table.index.values)]),
        salmon_merge_genes = expand(
            os.path.join(
                config["output_dir"],
                "summary_salmon",
                "quantmerge",
                "genes_{salmon_merge_on}.tsv"),
            salmon_merge_on=["tpm", "numreads"]),
        salmon_merge_transcripts = expand(
            os.path.join(
                config["output_dir"],
                "summary_salmon",
                "quantmerge",
                "transcripts_{salmon_merge_on}.tsv"),
            salmon_merge_on=["tpm", "numreads"])


rule create_index_star:
    """
        Create index for STAR alignments
    """
    input:
        genome = lambda wildcards:
            samples_table['genome']
            [samples_table['organism'] == wildcards.organism]
            [0],
        gtf = lambda wildcards:
            samples_table['gtf']
            [samples_table['organism'] == wildcards.organism]
            [0]

    output:
        chromosome_info = os.path.join(
            config['star_indexes'],
            "{organism}",
            "{index_size}",
            "STAR_index",
            "chrNameLength.txt"),
        chromosomes_names = os.path.join(
            config['star_indexes'],
            "{organism}",
            "{index_size}",
            "STAR_index",
            "chrName.txt")

    params:
        output_dir = os.path.join(
            config['star_indexes'],
            "{organism}",
            "{index_size}",
            "STAR_index"),
        outFileNamePrefix = os.path.join(
            config['star_indexes'],
            "{organism}",
            "{index_size}",
            "STAR_index/STAR_"),
        sjdbOverhang = "{index_size}"

    singularity:
        "docker://zavolab/star:2.7.3a-slim"

    threads: 12

    log:
        stderr = os.path.join(
            config['log_dir'],
            "{organism}_{index_size}_create_index_star.stderr.log"),
        stdout = os.path.join(
            config['log_dir'],
            "{organism}_{index_size}_create_index_star.stdout.log")

    shell:
        "(mkdir -p {params.output_dir}; \
        chmod -R 777 {params.output_dir}; \
        STAR \
        --runMode genomeGenerate \
        --sjdbOverhang {params.sjdbOverhang} \
        --genomeDir {params.output_dir} \
        --genomeFastaFiles {input.genome} \
        --runThreadN {threads} \
        --outFileNamePrefix {params.outFileNamePrefix} \
        --sjdbGTFfile {input.gtf}) \
        1> {log.stdout} 2> {log.stderr}"


rule create_index_salmon:
    """
        Create index for Salmon quantification
    """
    input:
        transcriptome = lambda wildcards:
            samples_table['tr_fasta_filtered']
            [samples_table['organism'] == wildcards.organism]
            [0]

    output:
        index = directory(
            os.path.join(
                config['salmon_indexes'],
                "{organism}",
                "{kmer}",
                "salmon.idx"))

    params:
        kmerLen = "{kmer}"

    singularity:
        "docker://zavolab/salmon:1.1.0-slim"

    log:
        stderr = os.path.join(
            config['log_dir'],
            "{organism}_{kmer}_create_index_salmon.stderr.log"),
        stdout = os.path.join(
            config['log_dir'],
            "{organism}_{kmer}_create_index_salmon.stdout.log")

    threads: 8

    shell:
        "(salmon index \
        --transcripts {input.transcriptome} \
        --index {output.index} \
        --kmerLen {params.kmerLen} \
        --threads {threads}) \
        1> {log.stdout} 2> {log.stderr}"


rule create_index_kallisto:
    """
        Create index for Kallisto quantification
    """
    input:
        transcriptome = lambda wildcards:
            samples_table['tr_fasta_filtered']
            [samples_table['organism'] == wildcards.organism]
            [0]

    output:
        index = os.path.join(
            config['kallisto_indexes'],
            "{organism}",
            "kallisto.idx")

    params:
        output_dir = os.path.join(
            config['kallisto_indexes'],
            "{organism}")

    singularity:
        "docker://zavolab/kallisto:0.46.1-slim"

    log:
        stderr = os.path.join(
            config['log_dir'],
            "{organism}_create_index_kallisto.stderr.log"),
        stdout = os.path.join(
            config['log_dir'],
            "{organism}_create_index_kallisto.stdout.log")

    shell:
        "(mkdir -p {params.output_dir}; \
        chmod -R 777 {params.output_dir}; \
        kallisto index -i {output.index} {input.transcriptome}) \
        1> {log.stdout}  2> {log.stderr}"


rule extract_transcripts_as_bed12:
    """
        Convert transcripts to BED12 format
    """
    input:
        gtf = lambda wildcards:
            samples_table['gtf']
            [0]

    output:
        bed12 = os.path.join(
            config['output_dir'],
            "full_transcripts_protein_coding.bed")

    singularity:
        "docker://zavolab/gtf_transcript_type_to_bed12:0.1.0-slim"

    threads: 1

    log:
        stderr = os.path.join(
            config['log_dir'],
            "extract_transcripts_as_bed12.stderr.log")

    shell:
        "(gtf_transcript_type_to_bed12.pl \
        --anno={input.gtf} \
        --type=protein_coding > {output.bed12}); \
        2> {log.stderr}"


rule calculate_TIN_scores:
    """
        Caluclate transcript integrity (TIN) score
    """
    input:
        bai = os.path.join(
            config['output_dir'],
            "{seqmode}",
            "{sample}",
            "map_genome",
            "{sample}_Aligned.sortedByCoord.out.bam.bai"),
        transcripts_bed12 = os.path.join(
            config['output_dir'],
            "full_transcripts_protein_coding.bed")

    output:
        TIN_score = os.path.join(
            config['output_dir'],
            "{seqmode}",
            "{sample}",
            "TIN",
            "TIN_score.tsv")

    params:
        bam = os.path.join(
            config['output_dir'],
            "{seqmode}",
            "{sample}",
            "map_genome",
            "{sample}_Aligned.sortedByCoord.out.bam"),
        sample = "{sample}"

    log:
        stderr = os.path.join(
            config['log_dir'],
            "{seqmode}",
            "{sample}",
            "calculate_TIN_scores.log")

    threads: 8

    singularity:
        "docker://zavolab/tin_score_calculation:0.1.0-slim"

    shell:
        "(tin_score_calculation.py \
        -i {params.bam} \
        -r {input.transcripts_bed12} \
        -c 0 \
        --names {params.sample} \
        -n 100 > {output.TIN_score};) 2> {log.stderr}"


rule salmon_quantmerge_genes:
    '''
        Merge gene quantifications into a single file
    '''
    input:
        salmon_in = expand(
            os.path.join(
                config["output_dir"],
                "{seqmode}",
                "{sample}",
                "salmon_quant",
                "quant.genes.sf"),
            zip,
            sample=list(samples_table.index.values),
            seqmode=list(samples_table["seqmode"]))

    output:
        salmon_out = os.path.join(
            config["output_dir"],
            "summary_salmon",
            "quantmerge",
            "genes_{salmon_merge_on}.tsv")

    params:
        salmon_dir = expand(
            os.path.join(
                config["output_dir"],
                "{seqmode}",
                "{sample}",
                "salmon_quant"),
            zip,
            sample=list(samples_table.index.values),
            seqmode=list(samples_table["seqmode"])),
        sample_name_list = expand(
            "{sample}",
            sample=list(samples_table.index.values)),
        salmon_merge_on = "{salmon_merge_on}"

    log:
        stderr = os.path.join(
            config["log_dir"],
            "salmon_quantmerge_genes_{salmon_merge_on}.stderr.log"),
        stdout = os.path.join(
            config["log_dir"],
            "salmon_quantmerge_genes_{salmon_merge_on}.stdout.log")

    threads: 1

    singularity:
        "docker://zavolab/salmon:1.1.0-slim"

    shell:
        "(salmon quantmerge \
        --quants {params.salmon_dir} \
        --genes \
        --names {params.sample_name_list} \
        --column {params.salmon_merge_on} \
        --output {output.salmon_out};) \
        1> {log.stdout} 2> {log.stderr}"


rule salmon_quantmerge_transcripts:
    '''
        Merge gene quantifications into a single file
    '''
    input:
        salmon_in = expand(
            os.path.join(
                config["output_dir"],
                "{seqmode}",
                "{sample}",
                "salmon_quant",
                "quant.sf"),
            zip,
            sample=list(samples_table.index.values),
            seqmode=list(samples_table["seqmode"])),

    output:
        salmon_out = os.path.join(
            config["output_dir"],
            "summary_salmon",
            "quantmerge",
            "transcripts_{salmon_merge_on}.tsv")

    params:
        salmon_dir = expand(
            os.path.join(
                config["output_dir"],
                "{seqmode}",
                "{sample}",
                "salmon_quant"),
            zip,
            sample=list(samples_table.index.values),
            seqmode=list(samples_table["seqmode"])),
        sample_name_list = expand(
            "{sample}",
            sample=list(samples_table.index.values)),
        salmon_merge_on = "{salmon_merge_on}"

    log:
        stderr = os.path.join(
            config["log_dir"],
            "salmon_quantmerge_transcripts_{salmon_merge_on}.stderr.log"),
        stdout = os.path.join(
            config["log_dir"],
            "salmon_quantmerge_transcripts_{salmon_merge_on}.stdout.log")

    threads: 1

    singularity:
        "docker://zavolab/salmon:1.1.0-slim"

    shell:
        "(salmon quantmerge \
        --quants {params.salmon_dir} \
        --names {params.sample_name_list} \
        --column {params.salmon_merge_on} \
        --output {output.salmon_out}) \
        1> {log.stdout} 2> {log.stderr}"

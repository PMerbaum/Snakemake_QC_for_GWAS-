#be sure plink and R with all required packages are in the environmet. Otherwise, add conda:"env.yaml" to rules
configfile: "config_snakemake.yaml"

rule all:
    input:
        expand("{{sample}}_clean.{ext}", ext=["bim","bed","fam"]),
        "{sample}_fail_het_mis_visualization.png",
        "{sample}_h38_snp_failedQC.txt"
        

#check which HRC genotype reference to use - 37 or 38! 
rule hrc_harmonization:
    input:
        "{sample}.bim"
    output:
        "{sample}_snps_exclude.txt",
        "{sample}_snps_flip.txt",
        "{sample}_snps_update.txt"
    script:
        "match_bim2hrc_sm.R" #37 to 38 by default

rule exclude_non_hrc:
    input:
        expand("{{sample}}.{ext}", ext=["bim","bed","fam"]),
        expand("{{sample}}_{ext}", ext=["snps_exclude.txt", "snps_flip.txt", "snps_update.txt"])
    output:
        expand("{{sample}}_hrc_ex.{ext}", ext=["bim","bed","fam"])
    params:
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4],
    shell:
        "plink --bfile {params.in_prefix} --exclude {input[3]} --make-bed --out {params.out_prefix}"


rule flip_hrc:
    input:
        expand("{{sample}}_hrc_ex.{ext}", ext=["bim","bed","fam"]),
        expand("{{sample}}_{ext}", ext=["snps_exclude.txt", "snps_flip.txt", "snps_update.txt"])
    output:
        expand("{{sample}}_flipped.{ext}", ext=["bim","bed","fam"])
    params:
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --flip {input[4]} --make-bed --out {params.out_prefix}"

rule update_hrc:
    input:
        expand("{{sample}}_flipped.{ext}", ext=["bim","bed","fam"]),
        expand("{{sample}}_{ext}", ext=["snps_exclude.txt", "snps_flip.txt", "snps_update.txt"])
    output:
        expand("{{sample}}_upd.{ext}", ext=["bim","bed","fam"])
    params:
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --update-name {input[5]} --make-bed --out {params.out_prefix}"

rule lift:
    input:
        expand("{{sample}}_upd.{ext}", ext=["bim"])
    output:
        "{sample}_lifted.txt",
        "{sample}_not_lifted.txt",
        "{sample}_to_upd.txt"
    log:
        'log/{sample}_lift.log'
    params:
        GChr_version = "hg19", #change to hg18 if needed 
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    script:
        "lift_sm.py" 

rule update_after_lift:
    input:
        expand("{{sample}}_upd.{ext}", ext=["bim","bed","fam"]), 
         "{sample}_lifted.txt",
        "{sample}_not_lifted.txt"
    output:
        expand("{{sample}}_h38.{ext}", ext=["bim","bed","fam"])
    params:
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "awk -F '\t' '{{print $2}}' {input[0]} | sort | uniq -d > multi.txt ; "
        "plink --bfile {params.in_prefix} --exclude multi.txt --make-bed --out {params.in_prefix}_dup_out ; "
        "plink --bfile {params.in_prefix}_dup_out --exclude {input[4]} --update-chr {input[3]} 1 2 --update-map {input[3]} 4 2 --make-bed --out {params.out_prefix}"


#here your actuall QC starts
rule exclude_missingness:
    input:
        expand("{{sample}}_h38.{ext}", ext=["bim","bed","fam"])
    output:
        expand("{{sample}}_nomiss.{ext}", ext=["bim","bed","fam"])
    params:
        mind = config["mind"],
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --missing --out {params.in_prefix} ; "
        "plink --bfile {params.in_prefix} --mind {params.mind} --make-bed --out {params.out_prefix}"

#Would not work if only 22 chr are present 
rule check_sex:
    input:
        expand("{{sample}}_nomiss.{ext}", ext=["bim","bed","fam"])
    output:
        expand("{{sample}}_sexchecked.{ext}", ext=["bim","bed","fam"])
        
    params:
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --check-sex ;" #think about the samples without phenotypes -> if someting is not 0, then ... 
        "grep PROBLEM plink.sexcheck > sexcheck_errors.txt ; "
        "plink --bfile {params.in_prefix} --remove sexcheck_errors.txt --make-bed --out {params.out_prefix}"

rule maf_hwe_geno: 
    input:
        expand("{{sample}}_sexchecked.{ext}", ext=["bim","bed","fam"])
    output:
        expand("{{sample}}_maf.{ext}", ext=["bim","bed","fam"])
    params:
        maf = config["maf"],
        hwe = config['hwe'],
        geno = config['geno'],
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --maf {params.maf} --hwe {params.hwe} --geno {params.geno} --make-bed --out {params.out_prefix}"

rule relatedness:
    input:
        expand("{{sample}}_maf.{ext}", ext=["bim","bed","fam"])
    output:
        expand("{{sample}}_related_filter.{ext}", ext=["bim","bed","fam"]),
        "{sample}.het",
        "{sample}_maf.genome"
    params:
        genome = config['genome'],
        PI_HAT = config['PI_HAT'],
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --genome --max {params.genome} --out {params.in_prefix} ; "
        "awk '$10 > {params.PI_HAT}' {params.in_prefix}.genome > {wildcards.sample}_relatives.txt ; "
        "awk '$10 < {params.genome}' {params.in_prefix}.genome > {wildcards.sample}_keep_relatedness.txt ; "
        "plink --bfile {params.in_prefix} --keep {wildcards.sample}_keep_relatedness.txt --make-bed --out {params.out_prefix} ; "
        "plink --bfile {params.out_prefix} --het --out {wildcards.sample}"

rule heterozygosity_script:
    input:
        expand("{{sample}}_related_filter.{ext}", ext=["bim","bed","fam"])
    output:
        expand("{{sample}}_hetfail.{ext}", ext=["txt"])
    script:
        "R-heterozygosity.R"

rule exclude_hetfail:
    input:
        expand("{{sample}}_hetfail.{ext}", ext=["txt"]),
        expand("{{sample}}_related_filter.{ext}", ext=["bim","bed","fam"])
    output:
        expand("{{sample}}_nohetfail.{ext}", ext=["bim","bed","fam"])
    params:
        in_prefix = lambda wildcards, input: input[1][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --exclude {input[0]} --make-bed --out {params.out_prefix}"

# #visualization and extracting clean data. Be sure R with all packages is available in the environment  
rule visualize_QC:
    input:
        "{sample}_h38.bim",
        "{sample}.het",
        "{sample}_maf.genome"
    output:
        "{sample}_fail_het_mis_visualization.png",
        "{sample}_h38_individuals_failedQC.txt"
    params:
        imissTh = config["imissTh"],
        highIBDTh = config['highIBDTh'],
        hetTh= config['hetTh'],
        maleTh=config['maleTh'],
        femaleTh=config['femaleTh']
    conda:
        "R4.2.yaml"
    script: 
        "visualization_plinkQC_sm.R"

rule marker_visualization:
    input:
        "{sample}_h38.bim",
        "{sample}_h38_individuals_failedQC.txt"
    output:
        "{sample}_h38_snp_failedQC.txt"
    params:
        lmissTh=config["lmissTh"],
        hweTh=config["hweTh"],
        macTh=config["macTh"],
        mafTh=config["mafTh"]
    # conda:
    #     "R4.2.yaml"
    script: 
        "marker_vis.R"

rule ancestry_check:
    input:
        expand("{{sample}}_nohetfail.{ext}", ext=["bim"]) #file after all other QC steps 
    output:
        expand("{{sample}}_nohetfail.hapmap3_r3_b38_dbsnp150_illumina_fwd.consensus.qc.poly.{ext}", ext=["eigenval","eigenvec"])
    params:
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-9]
    shell:
        "bash hapmap_anc_merge_sm.sh {params.in_prefix} {params.out_prefix}; " #creates a merged sample + hapmap file 
        "sed -i 's/hm3_//' {output[1]}" 


rule anestry_graph:
    input:
        expand("{{sample}}_nohetfail.hapmap3_r3_b38_dbsnp150_illumina_fwd.consensus.qc.poly.{ext}", ext=["eigenval","eigenvec"]),
        expand("{{sample}}_nohetfail.{ext}", ext=["bim"])
    output:
        "{sample}_nohetfail_ancestry.png",
        "{sample}_nohetfail_to_remove.txt"
    params:
        europeanTh=config['europeanTh']
    conda:
        "R4.2.yaml"
    script:
        "create_ancestry_data_sm.R"


rule clean_data:
    input:
        expand("{{sample}}_nohetfail.{ext}", ext=["bim","bed","fam"]),
        "{sample}_nohetfail_to_remove.txt"
    output:
         expand("{{sample}}_clean.{ext}", ext=["bim","bed","fam"])
    params:
        in_prefix = lambda wildcards, input: input[0][:-4],
        out_prefix = lambda wildcards, output: output[0][:-4]
    shell:
        "plink --bfile {params.in_prefix} --remove {input[3]} --make-bed --out {params.out_prefix} "

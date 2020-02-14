#!/bin/bash

# Tear down test environment
trap 'rm config.yaml samples.tsv && cd $user_dir' EXIT  # quotes command is exected after script exits, regardless of exit status
# 
# Set up test environment
set -eo pipefail  # ensures that script exits at first command that exits with non-zero status
set -u  # ensures that script exits when unset variables are used
set -x  # facilitates debugging by printing out executed commands
user_dir=$PWD
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd $script_dir

# Run tests
python "../../scripts/labkey_to_snakemake.py" \
    --input_table="input_table.tsv" \
    --input_dict="../../scripts/input_dict_caption.tsv" \
    --config_file="config.yaml" \
    --samples_table="samples.tsv" \
    --genomes_path="../input_files" \
    --multimappers='10' \
    # --remote \
    # --project_name "TEST_LABKEY" \
    # --query_name "RNA_Seq_data_template"


snakemake \
    --snakefile="../../snakemake/Snakefile" \
    --configfile="config.yaml" \
    --dryrun \
    # --rulegraph \
    # --printshellcmds \
    # | dot -Tpng > "rulegraph.png"

md5sum --check "expected_output.md5"

    # snakemake --rulegraph --configfile config.yaml | dot -Tpng > rulegraph.png


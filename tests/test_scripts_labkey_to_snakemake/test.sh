#!/bin/bash

# Scripts requires environment variables 'LABKEY_HOST', 'LABKEY_USER' and
# 'LABKEY_PASS' to be set with the appropriate values

# Tear down test environment
trap 'rm -rf ${HOME}/.netrc .snakemake config.yaml samples.tsv input_table.tsv && cd $user_dir' EXIT  # quotes command is exected after script exits, regardless of exit status

# Set up test environment
set -eo pipefail  # ensures that script exits at first command that exits with non-zero status
set -u  # ensures that script exits when unset variables are used
set -x  # facilitates debugging by printing out executed commands
user_dir=$PWD
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd $script_dir

cat << EOF | ( umask 0377; cat >> ${HOME}/.netrc; )
machine ${LABKEY_HOST}
login ${LABKEY_USER}
password ${LABKEY_PASS}
EOF

# Run tests
python "../../scripts/labkey_to_snakemake.py" \
    --input-dict="../../scripts/labkey_to_snakemake.dict.tsv" \
    --config-file="config.yaml" \
    --samples-table="samples.tsv" \
    --multimappers='10' \
    --remote \
    --project-name "TEST_LABKEY" \
    --table-name "RNA_Seq_data_template" \
    "../input_files"

# Check if dry run completes
snakemake \
    --snakefile="../../Snakefile" \
    --configfile="config.yaml" \
    --dryrun \

md5sum --check "expected_output.md5"
# MD5 sums obtained with command:
# md5sum config.yaml samples.tsv > expected_output.md5

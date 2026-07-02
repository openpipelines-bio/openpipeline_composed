#!/bin/bash

set -eo pipefail

# get the root of the directory
REPO_ROOT=$(git rev-parse --show-toplevel)

# ensure that the command below is run from the root of the repository
cd "$REPO_ROOT"

ID=pbmc_1k_protein_v3
OUT=resources_test/$ID
DIR=$(dirname "$OUT")

[ -d "$DIR" ] || mkdir -p "$DIR"

# dataset page:
# https://www.10xgenomics.com/resources/datasets/1-k-pbm-cs-from-a-healthy-donor-gene-expression-and-cell-surface-protein-3-standard-3-0-0

# download metrics summary
wget https://cf.10xgenomics.com/samples/cell-exp/3.0.0/pbmc_1k_protein_v3/pbmc_1k_protein_v3_metrics_summary.csv \
  -O "${OUT}_metrics_summary.csv"

# download counts h5 file
wget https://cf.10xgenomics.com/samples/cell-exp/3.0.0/pbmc_1k_protein_v3/pbmc_1k_protein_v3_filtered_feature_bc_matrix.h5 \
  -O "${OUT}_filtered_feature_bc_matrix.h5"

# wget https://cf.10xgenomics.com/samples/cell-exp/3.0.0/pbmc_1k_protein_v3/pbmc_1k_protein_v3_raw_feature_bc_matrix.h5 \
#   -O "${OUT}_raw_feature_bc_matrix.h5"

# # download counts matrix tar gz file
# wget https://cf.10xgenomics.com/samples/cell-exp/3.0.0/pbmc_1k_protein_v3/pbmc_1k_protein_v3_filtered_feature_bc_matrix.tar.gz \
#   -O "${OUT}_filtered_feature_bc_matrix.tar.gz"

# # extract matrix tar gz
# mkdir -p "${OUT}_filtered_feature_bc_matrix"
# tar -xvf "${OUT}_filtered_feature_bc_matrix.tar.gz" \
#   -C "${OUT}_filtered_feature_bc_matrix" \
#   --strip-components 1
# rm "${OUT}_filtered_feature_bc_matrix.tar.gz"


# convert 10x h5 to h5mu
nextflow run https://packages.viash-hub.com/vsh/openpipeline \
  -latest \
  -r v4.1.1 \
  -main-script target/nextflow/convert/from_10xh5_to_h5mu/main.nf \
  -profile docker \
  -c ./src/configs/labels_ci.config \
  --publish_dir $OUT \
  --input "${OUT}/${ID}_filtered_feature_bc_matrix.h5" \
  --input_metrics_summary "${OUT}/${ID}_metrics_summary.csv" \
  --output "${ID}_filtered_feature_bc_matrix.h5mu" \
  -resume

# run sample processing
nextflow \
  run https://packages.viash-hub.com/vsh/openpipeline \
  -latest \
  -r v4.1.1 \
  -main-script target/nextflow/workflows/multiomics/process_samples/main.nf \
  -c ./src/configs/labels_ci.config \
  -profile docker \
  --id pbmc_1k_protein_v3_uss \
  --input "${OUT}/${ID}_filtered_feature_bc_matrix.h5mu" \
  --output "${ID}_mms.h5mu" \
  --publishDir "$OUT" \
  -resume

# remove all files from the output folder except the final mms output
find "${OUT}" -mindepth 1 ! -name "${ID}_mms.h5mu" -delete

aws s3 sync \
  "$OUT" \
  s3://openpipelines-bio/openpipeline_composed/resources_test/"$ID" \
  --exclude "*.yaml" \
  --delete \
  --dryrun

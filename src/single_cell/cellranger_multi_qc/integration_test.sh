#!/bin/bash

set -eo pipefail

# get the root of the directory
REPO_ROOT=$(git rev-parse --show-toplevel)

# ensure that the command below is run from the root of the repository
cd "$REPO_ROOT"

# Run without optional QC reports (baseline)
# Uses GEX + Antibody Capture only (no VDJ) to avoid downloading the VDJ reference (~5 GB).
cat > /tmp/params_cellranger_multi_qc.yaml << EOF
param_list:
  - id: sample_anticmv
    input:
      - s3://openpipelines-data/10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R1_001.fastq.gz
      - s3://openpipelines-data/10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R2_001.fastq.gz
      - s3://openpipelines-data/10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R1_001.fastq.gz
      - s3://openpipelines-data/10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R2_001.fastq.gz
    gex_reference: s3://openpipelines-data/reference_gencodev41_chr1/reference_cellranger.tar.gz
    feature_reference: s3://openpipelines-data/10x_5k_anticmv/raw/feature_reference.csv
    library_id: "5k_human_antiCMV_T_TBNK_connect_GEX_1_subset;5k_human_antiCMV_T_TBNK_connect_AB_subset"
    library_type: "Gene Expression;Antibody Capture"
output_raw: "sample_anticmv_raw/"
output_h5mu: "sample_anticmv.h5mu"
create_sample_qc_report: true
output_qc_report: "sample_anticmv_qc_report_*.html"
output_processed_h5mu: "sample_anticmv_processed.h5mu"
publish_dir: test_output/cellranger_multi_qc
EOF

nextflow run target/nextflow/single_cell/cellranger_multi_qc/main.nf \
  -params-file /tmp/params_cellranger_multi_qc.yaml \
  -profile docker \
  -c src/configs/labels_ci.config \
  -resume

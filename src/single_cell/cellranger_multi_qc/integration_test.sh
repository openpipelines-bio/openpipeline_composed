#!/bin/bash

set -eo pipefail

# get the root of the directory
REPO_ROOT=$(git rev-parse --show-toplevel)

# ensure that the command below is run from the root of the repository
cd "$REPO_ROOT"

COMMON_ARGS=(
  run .
  -main-script src/single_cell/cellranger_multi_qc/test.nf
  -resume
  -profile docker
  -c src/configs/labels_ci.config
  -c src/configs/integration_tests.config
)

# test_wf: GEX + AB, sample QC report only
nextflow "${COMMON_ARGS[@]}" \
  -entry test_wf \
  --publish_dir test_output/cellranger_multi_qc/test_wf

# test_wf_ab_only: AB-only input, all report steps skipped
nextflow "${COMMON_ARGS[@]}" \
  -entry test_wf_ab_only \
  --publish_dir test_output/cellranger_multi_qc/test_wf_ab_only

# test_wf_both_reports: GEX + AB, both MultiQC and sample QC reports
nextflow "${COMMON_ARGS[@]}" \
  -entry test_wf_both_reports \
  --publish_dir test_output/cellranger_multi_qc/test_wf_both_reports

# test_wf_multiqc_only: GEX + AB, MultiQC report only
nextflow "${COMMON_ARGS[@]}" \
  -entry test_wf_multiqc_only \
  --publish_dir test_output/cellranger_multi_qc/test_wf_multiqc_only

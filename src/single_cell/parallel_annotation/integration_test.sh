#!/bin/bash

set -eo pipefail

# get the root of the directory
REPO_ROOT=$(git rev-parse --show-toplevel)

# ensure that the command below is run from the root of the repository
cd "$REPO_ROOT"

nextflow \
  run . \
  -main-script src/single_cell/parallel_annotation/test.nf \
  -entry test_wf \
  -resume \
  -profile docker \
  -c src/configs/labels_ci.config \
  -c src/configs/integration_tests.config \
  --publish_dir test

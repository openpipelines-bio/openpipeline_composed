#!/bin/bash

set -eo pipefail

# get the root of the directory
REPO_ROOT=$(git rev-parse --show-toplevel)

# ensure that the command below is run from the root of the repository
cd "$REPO_ROOT"

ID=annotation_test_data
OUT=resources_test/$ID/

# ideally, this would be a versioned pipeline run
[ -d "$OUT" ] || mkdir -p "$OUT"

# Download Tabula Sapiens Blood reference h5ad from https://doi.org/10.5281/zenodo.7587774
wget "https://zenodo.org/record/7587774/files/TS_Blood_filtered.h5ad?download=1" -O "${OUT}/tmp_TS_Blood_filtered.h5ad"

# Download Tabula Sapiens Blood pretrained model from https://doi.org/10.5281/zenodo.7580707
wget "https://zenodo.org/record/7580707/files/pretrained_models_Blood_ts.tar.gz?download=1" -O "${OUT}/tmp_pretrained_models_Blood_ts.tar.gz"


# Process Tabula Sapiens Blood reference h5ad
# Select one individual and 100 cells per cell type
# Add major types
# normalize and log1p transform data
python <<HEREDOC
import anndata as ad
import scanpy as sc
import numpy as np

# Read in data
ref_adata = ad.read_h5ad("${OUT}/tmp_TS_Blood_filtered.h5ad")
sub_ref_adata = ref_adata[ref_adata.obs["donor_assay"] == "TSP14_10x 3' v3"] 
n=100
s=sub_ref_adata.obs.groupby('cell_ontology_class').cell_ontology_class.transform('count')
sub_ref_adata_final = sub_ref_adata[sub_ref_adata.obs[s>=n].groupby('cell_ontology_class').head(n).index]

# Normalize and log1p transform data
data_for_scanpy = ad.AnnData(X=sub_ref_adata_final.X)
sc.pp.normalize_total(data_for_scanpy, target_sum=10000)
sc.pp.log1p(
    data_for_scanpy,
    base=None,
    layer=None,
    copy=False,
)
sub_ref_adata_final.layers["log_normalized"] = data_for_scanpy.X

# Add a two-level cell-type hierarchy for subtyping tests: every fine cell type
# (subtype) is nested under exactly one major cell type. The subtyping workflow
# splits the reference on major_cell_type and subtypes each major independently
# into its cell_type labels.
major_cell_type_map = {
    "classical monocyte": "myeloid",
    "neutrophil": "myeloid",
    "erythrocyte": "myeloid",
    "plasma cell": "lymphoid",
}
major_cell_type = sub_ref_adata_final.obs["cell_type"].astype(str).map(major_cell_type_map)
unmapped = sorted(sub_ref_adata_final.obs["cell_type"].astype(str)[major_cell_type.isna()].unique())
assert not unmapped, f"cell types missing a major_cell_type mapping: {unmapped}"
sub_ref_adata_final.obs["major_cell_type"] = major_cell_type.astype("category")

# The var index shares its name ("feature_name") with a var column of the same
# name. anndata refuses to write a MuData when the index name collides with a
# differently-typed column, so clear the index name before conversion. 
sub_ref_adata_final.var.index.name = None

# Write out data
sub_ref_adata_final.write("${OUT}/TS_Blood_filtered.h5ad", compression='gzip')
HEREDOC


echo "> Converting to h5mu"
cat > /tmp/from_h5ad_to_h5mu.yaml << HERE
input: "${OUT}/TS_Blood_filtered.h5ad"
output: "TS_Blood_filtered.h5mu"
modality: "rna"
HERE

nextflow \
  run https://packages.viash-hub.com/vsh/openpipeline \
  -r v4.1.1 \
  -main-script target/nextflow/convert/from_h5ad_to_h5mu/main.nf \
  --publish_dir "${OUT}" \
  -profile docker,mount_temp \
  -params-file /tmp/from_h5ad_to_h5mu.yaml \
  -c ./src/configs/labels_ci.config 


# echo "> Downloading pretrained CellTypist model and sample test data"
# wget https://celltypist.cog.sanger.ac.uk/models/Pan_Immune_CellTypist/v2/Immune_All_Low.pkl \
#     -O "${OUT}/celltypist_model_Immune_All_Low.pkl"
# wget https://celltypist.cog.sanger.ac.uk/Notebook_demo_data/demo_2000_cells.h5ad \
#     -O "${OUT}/demo_2000_cells.h5ad"

echo "> Converting to h5mu"
cat > /tmp/from_h5ad_to_h5mu_demo.yaml << HERE
input: "${OUT}/demo_2000_cells.h5ad"
output: "demo_2000_cells.h5mu"
modality: "rna"
HERE

nextflow \
  run https://packages.viash-hub.com/vsh/openpipeline \
  -r v4.1.1 \
  -main-script target/nextflow/convert/from_h5ad_to_h5mu/main.nf \
  --publish_dir "${OUT}" \
  -profile docker,mount_temp \
  -params-file /tmp/from_h5ad_to_h5mu_demo.yaml \
  -c ./src/configs/labels_ci.config 


echo "> Creating simple SCVI model"
cat > /tmp/simple_scvi.yaml << HERE
input: "${OUT}/TS_Blood_filtered.h5mu"
obs_batch: "donor_id"
var_gene_names: "ensemblid"
output: "scvi_output.h5mu"
output_model: "scvi_model"
max_epochs: 5
n_obs_min_count: 10
n_var_min_count: 10
HERE

nextflow \
  run https://packages.viash-hub.com/vsh/openpipeline \
  -r v4.1.1 \
  -main-script target/nextflow/integrate/scvi/main.nf \
  --publish_dir "${OUT}" \
  -profile docker,mount_temp \
  -params-file /tmp/simple_scvi.yaml \
  -c ./src/configs/labels_ci.config 

echo "> Creating SCVI model with covariates"
cat > /tmp/covariates_scvi.yaml << HERE
input: "${OUT}/TS_Blood_filtered.h5mu"
obs_batch: "donor_id"
obs_categorical_covariate: "assay"
obs_categorical_covariate: "donor_assay"
var_gene_names: "ensemblid"
output: "scvi_covariate_output.h5mu"
output_model: "scvi_covariate_model"
max_epochs: 5
n_obs_min_count: 10
n_var_min_count: 10
HERE

nextflow \
  run https://packages.viash-hub.com/vsh/openpipeline \
  -r v4.1.1 \
  -main-script target/nextflow/integrate/scvi/main.nf \
  --publish_dir "${OUT}" \
  -profile docker,mount_temp \
  -params-file /tmp/covariates_scvi.yaml \
  -c ./src/configs/labels_ci.config 

echo "> Creating simple SCANVI model"
cat > /tmp/simple_scanvi.yaml << HERE
input: "${OUT}/TS_Blood_filtered.h5mu"
scvi_model: "${OUT}/scvi_model"
obs_labels: "cell_ontology_class"
var_gene_names: "ensemblid"
output: "scanvi_output.h5mu"
output_model: "scanvi_model"
max_epochs: 5
HERE

nextflow \
  run https://packages.viash-hub.com/vsh/openpipeline \
  -r v4.1.1 \
  -main-script target/nextflow/annotate/scanvi/main.nf \
  --publish_dir "${OUT}" \
  -profile docker,mount_temp \
  -params-file /tmp/simple_scanvi.yaml \
  -c ./src/configs/labels_ci.config 

echo "> Creating SCANVI model with covariates"
cat > /tmp/covariates_scanvi.yaml << HERE
input: "${OUT}/TS_Blood_filtered.h5mu"
scvi_model: "${OUT}/scvi_covariate_model"
obs_labels: "cell_ontology_class"
var_gene_names: "ensemblid"
output: "scanvi_covariate_output.h5mu"
output_model: "scanvi_covariate_model"
max_epochs: 5
HERE

nextflow \
  run https://packages.viash-hub.com/vsh/openpipeline \
  -r v4.1.1 \
  -main-script target/nextflow/annotate/scanvi/main.nf \
  --publish_dir "${OUT}" \
  -profile docker,mount_temp \
  -params-file /tmp/covariates_scanvi.yaml \
  -c ./src/configs/labels_ci.config 


rm "${OUT}/scanvi_output.h5mu"
rm "${OUT}/scanvi_covariate_output.h5mu"
rm "${OUT}/scvi_output.h5mu"
rm "${OUT}/scvi_covariate_output.h5mu"
rm -f "${OUT}"/*.h5ad
rm -f "${OUT}"/*.state.yaml

aws s3 sync \
    resources_test/annotation_test_data \
    s3://openpipelines-bio/openpipeline_composed/resources_test/annotation_test_data \
    --dryrun --delete
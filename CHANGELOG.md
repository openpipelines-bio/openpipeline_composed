# openpipeline_composed x.x.x

## NEW FUNCTIONALITY

* `workflows/single_cell/parallel_annotation`: Add consensus voting based on per-method weighted probabilities via `--run_consensus` flag (default is true) (PR #22).

* `workflows/single_cell/process_integrate_annotate`: Expose the consensus voting step from `parallel_annotation` via `--run_consensus` (default is true) (PR #21).

* `workflows/single_cell/process_integrate_annotate`: Perform integration and annotation with multiple methods in parallel rather than sequentially using the `workflows/single_cell/parallel_annotation` and `workflows/single_cell/parallel_integration` workflows (PR #21).

* `workflows/single_cell/parallel_subtyping`: Add a workflow that subtypes each major cell type independently via reference-based label projection, splitting the reference by matching major cell type (`--reference_obs_major_cell_type`) so each type is subtyped against its own reference cells. Query cell types absent from the reference raise an error by default, or are passed through unannotated when `--allow_missing_reference_cell_type` is set. The subtype labels are combined into a single output h5mu (PR #23).

## MINOR CHANGES

* Migration of test resources to the package-specific `s3://openpipelines-bio/openpipeline_composed/resources_test` bucket (PR #24):

  - Add `.info.test_resources` to `_viash.yaml` to specify where test resources need to be synced from.
  - Test resources were regenerated via the scripts in `resources_test_scripts/`.

* Bump `openpipeline` dependency version to `v4.2.0` (PR #25).

# openpipeline_composed 0.2.1

## MAJOR CHANGES

* `workflows/single_cell/process_integrate_annotate`: Replace the inlined integration and annotation steps with the `single_cell/parallel_integration` and `single_cell/parallel_annotation` sub-workflows, so the selected methods run in parallel. This exposes the full set of methods: integration now also supports `scanorama` and `bbknn`, and annotation now also supports `harmony_knn`, `scvi_knn` and `singler`. The trained scVI and scANVI/scArches models are now emitted as optional outputs (`--output_scvi_model`, `--output_scanvi_model`).

## MINOR CHANGES

* Bump `openpipeline` dependency version to `v4.1.1` (PR #20).

# openpipeline_composed 0.2.0

## MAJOR CHANGES

* Bump `openpipeline` dependency version to `v4.1.0` and `openpipeline_qc` to `v0.3.0`, relevant updates include major changes to memory consumption and runtimes for and support for MuData encoded in Zarr format for `calculate_qc_metrics`, as well as updated defaults for annotation workflows (PR #17, PR #19).

## NEW FUNCTIONALITY

* `workflows/single_cell/parallel_integration`: Add a workflow that runs multiple integration methods (harmony, scvi, scanorama, bbknn) in parallel on a preprocessed h5mu and merges each method's annotations into a single output (PR #15).

* `workflows/single_cell/parallel_annotation`: Add a workflow that runs multiple annotation methods (celltypist, harmony_knn, scanvi_scarches, scvi_knn, singler) in parallel on a preprocessed query h5mu and merges each method's predictions into a single output (PR #16, PR #19).

* `dataflow/move_anndata_slots`: Add a component that moves selected slots (`.obs`, `.var`, `.obsm`, `.varm`, `.obsp`, `.varp`, `.uns`) from a modality in a source MuData file into a modality in a target MuData file (PR #15).

## MINOR CHANGES

* `workflows/single_cell/process_integrate_annotate`: Set scope to `private` (PR #6).

* Bump `openpipeline` dependency version to `v4.0.4` (PR #9).

* Bump `viash` version to `0.9.7` (PR #10).

# openpipeline_composed 0.1.1

## MINOR CHANGES

* Add a README (PR #4).

# openpipeline_composed 0.1.0

Initial release containing a single-cell meta-workflow to process single cell omics samples, perform batch integration and/or label projection.
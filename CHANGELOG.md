# openpipeline_composed x.x.x

## NEW FUNCTIONALITY

* `workflows/single_cell/parallel_integration`: Add a workflow that runs multiple integration methods (harmony, scvi, scanorama, bbknn) in parallel on a preprocessed h5mu and merges each method's annotations into a single output (PR #15).

## MINOR CHANGES

* `workflows/single_cell/process_integrate_annotate`: Set scope to `private` (PR #6).

* Bump `openpipeline` dependency version to `v4.0.4` (PR #9).

* Bump `viash` version to `0.9.7` (PR #10).

# openpipeline_composed 0.1.1

## MINOR CHANGES

* Add a README (PR #4).

# openpipeline_composed 0.1.0

Initial release containing a single-cell meta-workflow to process single cell omics samples, perform batch integration and/or label projection.
# openpipeline_composed 0.2.0

## MAJOR CHANGES

* Bump `openpipeline` dependency version to `v4.1.0` and `openpipeline_qc` to `v0.3.0`, relevant updates include major changes to memory consumption and runtimes for and support for MuData encoded in Zarr format for `calculate_qc_metrics` (PR #17).

## MINOR CHANGES

* `workflows/single_cell/process_integrate_annotate`: Set scope to `private` (PR #6).

* Bump `openpipeline` dependency version to `v4.0.4` (PR #9).

* Bump `viash` version to `0.9.7` (PR #10).

# openpipeline_composed 0.1.1

## MINOR CHANGES

* Add a README (PR #4).

# openpipeline_composed 0.1.0

Initial release containing a single-cell meta-workflow to process single cell omics samples, perform batch integration and/or label projection.
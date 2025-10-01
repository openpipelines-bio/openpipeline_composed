# OpenPipeline Composed

OpenPipeline Composed provides a comprehensive meta-workflow that combines multiple stand-alone workflows from the [OpenPipeline](https://github.com/openpipelines-bio/openpipeline/) package. The meta-workflow combines sample processing, batch integration, and cell type annotation into a unified pipeline for single-cell multi-omics data analysis.

[![ViashHub](https://img.shields.io/badge/ViashHub-openpipeline_composed-7a4baa.svg)](https://www.viash-hub.com/packages/openpipeline_composed)
[![GitHub](https://img.shields.io/badge/GitHub-openpipelines--bio%2Fopenpipeline_composed-blue.svg)](https://github.com/openpipelines-bio/openpipeline_composed)
[![GitHub License](https://img.shields.io/github/license/openpipelines-bio/openpipeline_composed.svg)](https://github.com/openpipelines-bio/openpipeline_composed/blob/main/LICENSE)
[![GitHub Issues](https://img.shields.io/github/issues/openpipelines-bio/openpipeline_composed.svg)](https://github.com/openpipelines-bio/openpipeline_composed/issues)
[![Viash version](https://img.shields.io/badge/Viash-v0.9.4-blue.svg)](https://viash.io)

## Overview

The sole purpose of this package is to provide a meta-workflow that orchestrates and combines various stand-alone workflows from the [OpenPipeline](https://github.com/openpipelines-bio/openpipeline/) package. By integrating multiple processing steps into a single workflow, it enables seamless processing from raw data to fully annotated, integrated datasets suitable for downstream analysis and atlas generation.

## Functionality

The meta-workflow combines three core OpenPipeline workflows:
- [**Sample Processing**](https://www.viash-hub.com/packages/openpipeline/latest/components/workflows/multiomics/process_samples): Initial quality control, filtering, and preprocessing
- [**Batch Integration**](https://www.viash-hub.com/packages/openpipeline/latest/components?search=workflows%2Fintegration): Integration using **Harmony** or **scVI** methods
- [**Cell Type Annotation**](https://www.viash-hub.com/packages/openpipeline/latest/components?search=workflows%2Fannotation): Annotation using **scANVI** or **CellTypist** methods

## Key Features

- 🔄 **End-to-End Processing**: Complete pipeline from raw data to annotated results
- 📊 **Atlas Generation**: Create comprehensive atlases from multiple datasets and sources
- 🔬 **Multi-Modal Support**: Process RNA-seq, ATAC-seq, protein, and spatial data
- 🎯 **Method Flexibility**: Choose from multiple integration and annotation approaches
- 🧬 **Reference Integration**: Leverage existing reference datasets for annotation

## Execution via CLI or Seqera Cloud

The openpipeline_composed package is available via [Viash Hub](https://www.viash-hub.com/packages/openpipeline_composed/latest/), where you can receive instructions on how to run the end-to-end workflow as well as individual subworkflows or components.

It's possible to run the workflow directly from Seqera Cloud. The necessary Nextflow schema files have been built and provided with the workflows in order to use the form-based input. However, Seqera Cloud can not deal with multiple-value parameters for batch processing of multiple samples. Therefore, it's better to use Viash Hub also here for launching the workflow on Seqera Cloud.

* Navigate to the [Viash Hub package page](https://www.viash-hub.com/packages/openpipeline_composed/latest/), select the workflow you want to launch and click the `launch` button.
* Select the execution environment of choice (e.g. `Seqera Cloud`, `Nextflow` or `Executable`)
* Fill in the form with the required parameters and launch the workflow.

## Support

For issues specific to the composed meta-workflow, please use the [GitHub issues tracker](https://github.com/openpipelines-bio/openpipeline_composed/issues). For general OpenPipeline questions, refer to the main [OpenPipeline documentation](https://openpipelines.bio/).

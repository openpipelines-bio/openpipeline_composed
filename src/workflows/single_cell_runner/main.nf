workflow run_wf {
  take:
    input_ch

  main:
    output_ch = input_ch
    | map { id, state ->
      def new_state = state + [ "query_processed": state.output, "_meta": ["join_id": id] ]
      [id, new_state]
    }
    // Make sure parameters are filled out correctly
    | map { id, state ->
      def new_state = [:]
      // Check that at least one of annotation_methods or integration_methods is not empty
      if ((!state.annotation_methods || state.annotation_methods.isEmpty()) && 
          (!state.integration_methods || state.integration_methods.isEmpty())) {
        throw new RuntimeException("At least one of --annotation_methods or --integration_methods must be provided and non-empty.")
      }
      // Check CellTypist arguments
      if (state.annotation_methods.contains("celltypist") && 
        (!state.celltypist_model && !state.reference)) {
        throw new RuntimeException("Celltypist was selected as an annotation method. Either --celltypist_model or --reference must be provided.")
      }
      if (state.annotation_methods.contains("celltypist") && state.celltypist_model && state.reference )  {
        System.err.println(
          "Warning: --celltypist_model is set and a --reference was provided. \
          The pre-trained Celltypist model will be used for annotation, the reference will be ignored."
        )
      }

      [id, state + new_state]
    }
    | process_samples_workflow.run(
      fromState: [
        "input": "input", 
        "id": "id",
        "rna_layer": "input_layer",
        "rna_min_counts": "rna_min_counts",
        "rna_max_counts": "rna_max_counts",
        "rna_min_genes_per_cell": "rna_min_genes_per_cell",
        "rna_max_genes_per_cell": "rna_max_genes_per_cell",
        "rna_min_cells_per_gene": "rna_min_cells_per_gene",
        "rna_min_fraction_mito": "rna_min_fraction_mito",
        "rna_max_fraction_mito": "rna_max_fraction_mito",
        "rna_min_fraction_ribo": "rna_min_fraction_ribo",
        "rna_max_fraction_ribo": "rna_max_fraction_ribo",
        "var_name_mitochondrial_genes": "var_name_mitochondrial_genes",
        "var_name_ribosomal_genes": "var_name_ribosomal_genes",
        "var_gene_names": "input_var_gene_names",
        "mitochondrial_gene_regex": "mitochondrial_gene_regex",
        "ribosomal_gene_regex": "ribosomal_gene_regex",
        "var_qc_metrics": "var_qc_metrics"
      ],
      args: [
        "pca_overwrite": "true",
        "add_id_obs_output": "sample_id",
        "highly_variable_features_var_output": "filter_with_hvg_query"
      ],
      toState: ["query_processed": "output"], 
    )
    // Integration methods
    | harmony_integration.run(
      runIf: { id, state -> 
        state.integration_methods.contains("harmony") 
      },
      fromState: [ 
        "id": "id",
        "input": "query_processed",
        "modality": "modality",
        "theta": "harmony_theta",
        "leiden_resolution": "leiden_resolution",
        "obs_covariates": "harmony_obs_covariates",
      ],
      args: [
        "layer": "log_normalized",
        "embedding": "X_pca",
        "obsm_integrated": "X_harmony_integrated",
        "uns_neighbors": "harmony_integration_neighbors",
        "obsp_neighbor_distances": "harmony_integration_neighbor_distances",
        "obsp_neighbor_connectivities": "harmony_integration_neighbor_connectivities",
        "obs_cluster": "harmony_integration_leiden",
        "obsm_umap": "X_harmony_umap"
      ],
      toState: [ "query_processed": "output" ]
    )

    | scvi_integration.run(
      runIf: { id, state -> 
        state.integration_methods.contains("scvi")
      },
      fromState: [ 
        "id": "id",
        "input": "query_processed",
        "layer": "input_layer",
        "modality": "modality",
        "leiden_resolution": "leiden_resolution",
        "early_stopping": "early_stopping",
        "early_stopping_monitor": "early_stopping_monitor",
        "early_stopping_patience": "early_stopping_patience",
        "early_stopping_min_delta": "early_stopping_min_delta",
        "max_epochs": "max_epochs",
        "reduce_lr_on_plateau": "reduce_lr_on_plateau",
        "lr_factor": "lr_factor",
        "lr_patience": "lr_patience"
      ],
      args: [
        "obsm_output": "X_scvi_integrated",
        "obs_batch": "sample_id",
        "var_input": "filter_with_hvg_query",
        "uns_neighbors": "scvi_integration_neighbors",
        "obsp_neighbor_distances": "scvi_integration_neighbor_distances",
        "obsp_neighbor_connectivities": "scvi_integration_neighbor_connectivities",
        "obs_cluster": "scvi_integration_leiden",
        "obsm_umap": "X_scvi_umap"
      ],
      toState: [ "query_processed": "output", "scvi_model": "output_model" ]
    )
    // Annotation methods
    | celltypist_annotation.run(
      runIf: { id, state -> state.annotation_methods.contains("celltypist") && state.celltypist_model },
      fromState: [ 
        "input": "query_processed",
        "modality": "modality",
        "input_var_gene_names": "input_var_gene_names",
        "input_reference_gene_overlap": "input_reference_gene_overlap",
        "model": "celltypist_model",
        "majority_voting": "celltypist_majority_voting"
      ],
      args: [
        // log normalized counts are expected for celltypist
        "input_layer": "log_normalized",
        "output_obs_predictions": "celltypist_pred",
        "output_obs_probability": "celltypist_proba"
      ],
      toState: [ "query_processed": "output" ]
    )

    | celltypist_annotation.run(
      runIf: { id, state -> state.annotation_methods.contains("celltypist") && !state.celltypist_model },
      fromState: [
        "input": "query_processed",
        "modality": "modality",
        "input_var_gene_names": "input_var_gene_names",
        "input_reference_gene_overlap": "input_reference_gene_overlap",
        "reference": "reference",
        "reference_layer": "reference_layer_lognormalized_counts",
        "reference_obs_target": "reference_obs_label",
        "reference_var_gene_names": "reference_var_gene_names",
        "reference_obs_batch": "reference_obs_batch",
        "reference_var_input": "reference_var_input",
        "feature_selection": "celltypist_feature_selection",
        "C": "celltypist_C",
        "max_iter": "celltypist_max_iter",
        "use_SGD": "celltypist_use_SGD",
        "min_prop": "celltypist_min_prop",
        "majority_voting": "celltypist_majority_voting"
      ],
      args: [
        // log normalized counts are expected for celltypist
        "input_layer": "log_normalized",
        "output_obs_predictions": "celltypist_pred",
        "output_obs_probability": "celltypist_proba"
      ],
      toState: [ "query_processed": "output" ]
    )

    | scanvi_scarches_annotation.run(
      runIf: { id, state -> state.annotation_methods.contains("scanvi_scarches")},
      fromState: [
        "id": "id",
        "input": "query_processed",
        "modality": "modality",
        "layer": "input_layer",
        "input_var_gene_names": "input_var_gene_names",
        "reference": "reference",
        "reference_obs_target": "reference_obs_label",
        "reference_obs_batch_label": "reference_obs_batch",
        "reference_var_hvg": "reference_var_input",
        "reference_var_gene_names": "reference_var_gene_names",
        "unlabeled_category": "reference_obs_label_unlabeled_category",
        "early_stopping": "early_stopping",
        "early_stopping_monitor": "early_stopping_monitor",
        "early_stopping_patience": "early_stopping_patience",
        "early_stopping_min_delta": "early_stopping_min_delta",
        "max_epochs": "max_epochs",
        "reduce_lr_on_plateau": "reduce_lr_on_plateau",
        "lr_factor": "lr_factor",
        "lr_patience": "lr_patience",
        "leiden_resolution": "leiden_resolution",
        "knn_weights": "knn_weights",
        "knn_n_neighbors": "knn_n_neighbors"
      ],
      args: [
        "input_obs_batch_label": "sample_id",
        "output_obs_predictions": "scanvi_knn_pred",
        "output_obs_probability": "scanvi_knn_proba"
      ],
      toState: [ "query_processed": "output" ]
    )

    | map {id, state ->
      def new_state = state + ["output": state.query_processed]
      [id, new_state]
    }

    | setState(["output", "_meta"])

  emit:
    output_ch
}
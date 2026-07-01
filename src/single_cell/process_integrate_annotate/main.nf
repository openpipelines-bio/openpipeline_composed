workflow run_wf {
  take:
    input_ch

  main:
    output_ch = input_ch
    | map { id, state ->
      def new_state = state + [ "_meta": ["join_id": id] ]
      [id, new_state]
    }
    // Make sure at least one method is requested. Method-specific requirements
    // (e.g. celltypist needing a model or reference, reference-based methods
    // needing a labeled reference) are validated inside the parallel sub-workflows.
    | map { id, state ->
      if (!state.annotation_methods && !state.integration_methods) {
        throw new RuntimeException("At least one of --annotation_methods or --integration_methods must be provided")
      }
      [id, state]
    }
    | process_samples_workflow.run(
      fromState: [
        "input": "input",
        "id": "id",
        // Modality input layers
        "rna_layer": "input_layer",
        "prot_layer": "prot_layer",
        "gdo_layer": "gdo_layer",
        // RNA filtering
        "rna_min_counts": "rna_min_counts",
        "rna_max_counts": "rna_max_counts",
        "rna_min_genes_per_cell": "rna_min_genes_per_cell",
        "rna_max_genes_per_cell": "rna_max_genes_per_cell",
        "rna_min_cells_per_gene": "rna_min_cells_per_gene",
        "rna_min_fraction_mito": "rna_min_fraction_mito",
        "rna_max_fraction_mito": "rna_max_fraction_mito",
        "rna_min_fraction_ribo": "rna_min_fraction_ribo",
        "rna_max_fraction_ribo": "rna_max_fraction_ribo",
        "skip_scrublet_doublet_detection": "skip_scrublet_doublet_detection",
        // Protein (CITE-seq) filtering
        "prot_min_counts": "prot_min_counts",
        "prot_max_counts": "prot_max_counts",
        "prot_min_proteins_per_cell": "prot_min_proteins_per_cell",
        "prot_max_proteins_per_cell": "prot_max_proteins_per_cell",
        "prot_min_cells_per_protein": "prot_min_cells_per_protein",
        // GDO filtering
        "gdo_min_counts": "gdo_min_counts",
        "gdo_max_counts": "gdo_max_counts",
        "gdo_min_guides_per_cell": "gdo_min_guides_per_cell",
        "gdo_max_guides_per_cell": "gdo_max_guides_per_cell",
        "gdo_min_cells_per_guide": "gdo_min_cells_per_guide",
        // Cross-modality filtering
        "intersect_obs": "intersect_obs",
        // Sample ID handling
        "add_id_make_observation_keys_unique": "add_id_make_observation_keys_unique",
        // Mitochondrial & ribosomal gene detection
        "obs_name_mitochondrial_fraction": "obs_name_mitochondrial_fraction",
        "obs_name_ribosomal_fraction": "obs_name_ribosomal_fraction",
        "var_name_mitochondrial_genes": "var_name_mitochondrial_genes",
        "var_name_ribosomal_genes": "var_name_ribosomal_genes",
        "var_gene_names": "input_var_gene_names",
        "mitochondrial_gene_regex": "mitochondrial_gene_regex",
        "ribosomal_gene_regex": "ribosomal_gene_regex",
        // QC metrics
        "var_qc_metrics": "var_qc_metrics",
        "top_n_vars": "top_n_vars",
        // Highly variable features detection
        "highly_variable_features_obs_batch_key": "highly_variable_features_obs_batch_key",
        // CLR (protein normalization)
        "clr_axis": "clr_axis",
        // RNA scaling
        "rna_enable_scaling": "rna_enable_scaling",
        "rna_scaling_output_layer": "rna_scaling_output_layer",
        "rna_scaling_max_value": "rna_scaling_max_value",
        "rna_scaling_zero_center": "rna_scaling_zero_center",
        "rna_scaling_pca_obsm_output": "rna_scaling_pca_obsm_output",
        "rna_scaling_pca_loadings_varm_output": "rna_scaling_pca_loadings_varm_output",
        "rna_scaling_pca_variance_uns_output": "rna_scaling_pca_variance_uns_output",
        "rna_scaling_umap_obsm_output": "rna_scaling_umap_obsm_output"
      ],
      args: [
        "pca_overwrite": "true",
        "add_id_obs_output": "sample_id",
        "highly_variable_features_var_output": "filter_with_hvg_query"
      ],
      toState: ["query_processed": "output"],
    )
    // Integration: run the selected methods in parallel and merge their
    // embeddings, cluster labels and neighbor graphs into a single h5mu.
    | parallel_integration.run(
      runIf: { id, state -> state.integration_methods },
      fromState: { id, state -> [
        "id": state.id,
        "input": state.query_processed,
        "modality": state.modality,
        // Layers, embedding, batch and HVG slots are produced by process_samples
        // with these fixed names.
        "layer_log_normalized_counts": "log_normalized",
        "layer_raw_counts": state.input_layer,
        "obsm_embedding": "X_pca",
        "obs_batch": "sample_id",
        "var_input": "filter_with_hvg_query",
        "integration_methods": state.integration_methods,
        "obs_covariates": state.harmony_obs_covariates,
        "harmony_theta": state.harmony_theta,
        "obs_categorical_covariates": state.obs_categorical_covariates,
        "obs_numerical_covariates": state.obs_numerical_covariates,
        "scanorama_knn": state.scanorama_knn,
        "scanorama_batch_size": state.scanorama_batch_size,
        "scanorama_sigma": state.scanorama_sigma,
        "scanorama_approx": state.scanorama_approx,
        "scanorama_alpha": state.scanorama_alpha,
        "bbknn_n_neighbors_within_batch": state.bbknn_n_neighbors_within_batch,
        "bbknn_n_pcs": state.bbknn_n_pcs,
        "bbknn_n_trim": state.bbknn_n_trim,
        "leiden_resolution": state.leiden_resolution,
        "scvi_early_stopping": state.early_stopping,
        "scvi_early_stopping_monitor": state.early_stopping_monitor,
        "scvi_early_stopping_patience": state.early_stopping_patience,
        "scvi_early_stopping_min_delta": state.early_stopping_min_delta,
        "scvi_max_epochs": state.max_epochs,
        "scvi_reduce_lr_on_plateau": state.reduce_lr_on_plateau,
        "scvi_lr_factor": state.lr_factor,
        "scvi_lr_patience": state.lr_patience,
        "output_compression": state.output_compression
      ]},
      toState: [ "query_processed": "output", "output_scvi_model": "output_scvi_model" ]
    )
    // Annotation: run the selected methods in parallel and merge their
    // predictions, probabilities and embeddings into a single h5mu.
    | parallel_annotation.run(
      runIf: { id, state -> state.annotation_methods },
      fromState: { id, state -> [
        "id": state.id,
        "input": state.query_processed,
        "modality": state.modality,
        "input_layer": state.input_layer,
        "input_layer_lognormalized": "log_normalized",
        "input_obs_batch_label": "sample_id",
        "input_var_gene_names": state.input_var_gene_names,
        "input_reference_gene_overlap": state.input_reference_gene_overlap,
        "sanitize_ensembl_ids": state.sanitize_ensembl_ids,
        "input_obs_categorical_covariates": state.input_obs_categorical_covariates,
        "input_obs_numerical_covariates": state.input_obs_numerical_covariates,
        "annotation_methods": state.annotation_methods,
        "reference": state.reference,
        "reference_layer": state.reference_layer_raw_counts,
        "reference_layer_lognormalized": state.reference_layer_lognormalized_counts,
        "reference_obs_target": state.reference_obs_label,
        "reference_obs_batch_label": state.reference_obs_batch,
        "reference_var_gene_names": state.reference_var_gene_names,
        "reference_var_input": state.reference_var_input,
        "reference_obs_categorical_covariates": state.reference_obs_categorical_covariates,
        "reference_obs_numerical_covariates": state.reference_obs_numerical_covariates,
        "reference_obs_label_unlabeled_category": state.reference_obs_label_unlabeled_category,
        "leiden_resolution": state.leiden_resolution,
        "knn_weights": state.knn_weights,
        "knn_n_neighbors": state.knn_n_neighbors,
        "scvi_early_stopping": state.early_stopping,
        "scvi_early_stopping_monitor": state.early_stopping_monitor,
        "scvi_early_stopping_patience": state.early_stopping_patience,
        "scvi_early_stopping_min_delta": state.early_stopping_min_delta,
        "scvi_max_epochs": state.max_epochs,
        "scvi_reduce_lr_on_plateau": state.reduce_lr_on_plateau,
        "scvi_lr_factor": state.lr_factor,
        "scvi_lr_patience": state.lr_patience,
        "celltypist_model": state.celltypist_model,
        "celltypist_majority_voting": state.celltypist_majority_voting,
        "celltypist_feature_selection": state.celltypist_feature_selection,
        "celltypist_C": state.celltypist_C,
        "celltypist_max_iter": state.celltypist_max_iter,
        "celltypist_use_SGD": state.celltypist_use_SGD,
        "celltypist_min_prop": state.celltypist_min_prop,
        "harmony_knn_n_hvg": state.harmony_knn_n_hvg,
        "harmony_knn_pca_num_components": state.harmony_knn_pca_num_components,
        "harmony_knn_theta": state.harmony_knn_theta,
        "scvi_knn_n_hvg": state.scvi_knn_n_hvg,
        "singler_input_obs_clusters": state.singler_input_obs_clusters,
        "singler_de_method": state.singler_de_method,
        "singler_de_n_genes": state.singler_de_n_genes,
        "singler_quantile": state.singler_quantile,
        "singler_fine_tune": state.singler_fine_tune,
        "singler_fine_tuning_threshold": state.singler_fine_tuning_threshold,
        "singler_prune": state.singler_prune,
        "output_compression": state.output_compression
      ]},
      toState: [ "query_processed": "output", "output_scanvi_model": "output_scanvi_model" ]
    )

    | map { id, state ->
      def out = ["output": state.query_processed]
      // The trained models are only present when their producing method ran.
      if (state.output_scvi_model) {
        out["output_scvi_model"] = state.output_scvi_model
      }
      if (state.output_scanvi_model) {
        out["output_scanvi_model"] = state.output_scanvi_model
      }
      [id, state + out]
    }

    | setState(["output", "output_scvi_model", "output_scanvi_model", "_meta"])

  emit:
    output_ch
}

workflow run_wf {
  take:
    input_ch

  main:
    output_ch = input_ch
    // === Validate method-specific requirements ===
    // Fail early when a selected method's required inputs are missing, rather
    // than surfacing the error deep inside a sub-workflow.
    | map { id, state ->
        def methods = state.annotation_methods
        // CellTypist needs either a pretrained model or a reference to train on.
        if (methods.contains("celltypist") && !state.celltypist_model && !state.reference) {
          throw new RuntimeException(
            "celltypist was selected but neither --celltypist_model nor --reference " +
            "is provided; one of them is required."
          )
        }
        if (methods.contains("celltypist") && state.celltypist_model && state.reference) {
          System.err.println(
            "Warning: both --celltypist_model and --reference are set for celltypist; " +
            "the pretrained model will be used and the reference ignored."
          )
        }
        // The reference-based methods need a labeled reference.
        def reference_methods = methods.findAll { method ->
          method in ["harmony_knn", "scanvi_scarches", "scvi_knn"]
        }
        if (reference_methods && (!state.reference || !state.reference_obs_target)) {
          throw new RuntimeException(
            "Methods ${reference_methods} require a labeled reference, but " +
            "--reference and/or --reference_obs_target is not set."
          )
        }
        [id, state]
      }
    | map { id, state ->
        def new_state = state + [
          "merged": state.input,
          "_meta": ["join_id": id]
        ]
        [id, new_state]
      }

    // === Parallel annotation runs ===
    // Each .run() below reads state.input (the ORIGINAL preprocessed query),
    // NOT the previous step's output. Nextflow's DAG scheduler therefore sees
    // no dependency between these calls and executes them concurrently.

    // CellTypist: two mutually-exclusive branches.
    // Branch 1: a pretrained model is provided (no reference needed).
    | celltypist_annotation.run(
        key: "celltypist_with_model",
        runIf: { id, state ->
          state.annotation_methods.contains("celltypist") && state.celltypist_model
        },
        fromState: [
          "input": "input",
          "modality": "modality",
          "input_layer": "input_layer",
          "input_var_gene_names": "input_var_gene_names",
          "input_reference_gene_overlap": "input_reference_gene_overlap",
          "model": "celltypist_model",
          "majority_voting": "celltypist_majority_voting",
          "output_obs_predictions": "celltypist_obs_predictions",
          "output_obs_probability": "celltypist_obs_probability"
        ],
        toState: ["celltypist_output": "output"]
      )
    // Branch 2: no pretrained model — train from --reference.
    | celltypist_annotation.run(
        key: "celltypist_with_reference",
        runIf: { id, state ->
          state.annotation_methods.contains("celltypist") && !state.celltypist_model
        },
        fromState: [
          "input": "input",
          "modality": "modality",
          "input_layer": "input_layer",
          "input_var_gene_names": "input_var_gene_names",
          "input_reference_gene_overlap": "input_reference_gene_overlap",
          "reference": "reference",
          "reference_layer": "reference_layer",
          "reference_obs_target": "reference_obs_target",
          "reference_obs_batch": "reference_obs_batch_label",
          "reference_var_gene_names": "reference_var_gene_names",
          "reference_var_input": "reference_var_input",
          "feature_selection": "celltypist_feature_selection",
          "majority_voting": "celltypist_majority_voting",
          "C": "celltypist_C",
          "max_iter": "celltypist_max_iter",
          "use_SGD": "celltypist_use_SGD",
          "min_prop": "celltypist_min_prop",
          "output_obs_predictions": "celltypist_obs_predictions",
          "output_obs_probability": "celltypist_obs_probability"
        ],
        toState: ["celltypist_output": "output"]
      )
    | harmony_knn_annotation.run(
        runIf: { id, state -> state.annotation_methods.contains("harmony_knn") },
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "input_layer": "input_layer_lognormalized",
          "input_obs_batch_label": "input_obs_batch_label",
          "input_var_gene_names": "input_var_gene_names",
          "input_reference_gene_overlap": "input_reference_gene_overlap",
          "reference": "reference",
          "reference_layer": "reference_layer_lognormalized",
          "reference_obs_target": "reference_obs_target",
          "reference_obs_batch_label": "reference_obs_batch_label",
          "reference_var_gene_names": "reference_var_gene_names",
          "n_hvg": "harmony_knn_n_hvg",
          "pca_num_components": "harmony_knn_pca_num_components",
          "harmony_theta": "harmony_knn_theta",
          "leiden_resolution": "leiden_resolution",
          "knn_weights": "knn_weights",
          "knn_n_neighbors": "knn_n_neighbors",
          "output_obs_predictions": "harmony_knn_obs_predictions",
          "output_obs_probability": "harmony_knn_obs_probability",
          "output_obsm_integrated": "harmony_knn_obsm_integrated"
        ],
        toState: ["harmony_knn_output": "output"]
      )
    | scanvi_scarches_annotation.run(
        runIf: { id, state -> state.annotation_methods.contains("scanvi_scarches") },
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "layer": "input_layer",
          "input_obs_batch_label": "input_obs_batch_label",
          "input_var_gene_names": "input_var_gene_names",
          "reference": "reference",
          "reference_obs_target": "reference_obs_target",
          "reference_obs_batch_label": "reference_obs_batch_label",
          "unlabeled_category": "reference_obs_label_unlabeled_category",
          "reference_var_hvg": "reference_var_input",
          "reference_var_gene_names": "reference_var_gene_names",
          "input_obs_categorical_covariate": "input_obs_categorical_covariates",
          "input_obs_continuous_covariate": "input_obs_numerical_covariates",
          "reference_obs_categorical_covariate": "reference_obs_categorical_covariates",
          "reference_obs_continuous_covariate": "reference_obs_numerical_covariates",
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
          "knn_n_neighbors": "knn_n_neighbors",
          "output_obs_predictions": "scanvi_scarches_obs_predictions",
          "output_obs_probability": "scanvi_scarches_obs_probability",
          "output_obsm_integrated": "scanvi_scarches_obsm_integrated"
        ],
        toState: [
          "scanvi_scarches_output": "output",
          "scanvi_scarches_model": "output_model"
        ]
      )
    | scvi_knn_annotation.run(
        runIf: { id, state -> state.annotation_methods.contains("scvi_knn") },
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "input_layer": "input_layer",
          "input_layer_lognormalized": "input_layer_lognormalized",
          "input_obs_batch_label": "input_obs_batch_label",
          "input_var_gene_names": "input_var_gene_names",
          "input_reference_gene_overlap": "input_reference_gene_overlap",
          "reference": "reference",
          "reference_layer": "reference_layer",
          "reference_layer_lognormalized": "reference_layer_lognormalized",
          "reference_obs_target": "reference_obs_target",
          "reference_obs_batch_label": "reference_obs_batch_label",
          "reference_var_gene_names": "reference_var_gene_names",
          "n_hvg": "scvi_knn_n_hvg",
          // scvi_knn re-exposes scVI training hparams under a `scvi_` prefix.
          "scvi_early_stopping": "early_stopping",
          "scvi_early_stopping_monitor": "early_stopping_monitor",
          "scvi_early_stopping_patience": "early_stopping_patience",
          "scvi_early_stopping_min_delta": "early_stopping_min_delta",
          "scvi_max_epochs": "max_epochs",
          "scvi_reduce_lr_on_plateau": "reduce_lr_on_plateau",
          "scvi_lr_factor": "lr_factor",
          "scvi_lr_patience": "lr_patience",
          "leiden_resolution": "leiden_resolution",
          "knn_weights": "knn_weights",
          "knn_n_neighbors": "knn_n_neighbors",
          "output_obs_predictions": "scvi_knn_obs_predictions",
          "output_obs_probability": "scvi_knn_obs_probability",
          "output_obsm_integrated": "scvi_knn_obsm_integrated"
        ],
        toState: ["scvi_knn_output": "output"]
      )

    // === Sequential merge of per-method annotations ===
    // Each move_slots call depends on state.merged from the previous one, so
    // these run in order. move_anndata_slots copies the specified slots from
    // the method's output h5mu into the running merged target.
    | move_slots.run(
        key: "move_celltypist_slots",
        runIf: { id, state -> state.annotation_methods.contains("celltypist") },
        fromState: { id, state ->
          [
            "input_source": state.celltypist_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": [state.celltypist_obs_predictions, state.celltypist_obs_probability],
            // celltypist produces no integrated embedding — obs only.
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )
    | move_slots.run(
        key: "move_harmony_knn_slots",
        runIf: { id, state -> state.annotation_methods.contains("harmony_knn") },
        fromState: { id, state ->
          [
            "input_source": state.harmony_knn_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": [state.harmony_knn_obs_predictions, state.harmony_knn_obs_probability],
            "obsm": [state.harmony_knn_obsm_integrated],
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )
    | move_slots.run(
        key: "move_scanvi_scarches_slots",
        runIf: { id, state -> state.annotation_methods.contains("scanvi_scarches") },
        fromState: { id, state ->
          [
            "input_source": state.scanvi_scarches_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": [state.scanvi_scarches_obs_predictions, state.scanvi_scarches_obs_probability],
            "obsm": [state.scanvi_scarches_obsm_integrated],
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )
    | move_slots.run(
        key: "move_scvi_knn_slots",
        runIf: { id, state -> state.annotation_methods.contains("scvi_knn") },
        fromState: { id, state ->
          [
            "input_source": state.scvi_knn_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": [state.scvi_knn_obs_predictions, state.scvi_knn_obs_probability],
            "obsm": [state.scvi_knn_obsm_integrated],
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )

    | map { id, state ->
        def out = ["output": state.merged]
        // scanvi_scarches_model is only present when scanvi_scarches was selected.
        if (state.scanvi_scarches_model) {
          out["output_scanvi_model"] = state.scanvi_scarches_model
        }
        [id, state + out]
      }
    | setState(["output", "output_scanvi_model", "_meta"])

  emit:
    output_ch
}

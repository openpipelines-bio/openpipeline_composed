workflow run_wf {
  take:
    input_ch

  main:
    integration_ch = input_ch
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
          method in ["harmony_knn", "scanvi_scarches", "scvi_knn", "singler"]
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
    // Each method reads from `integration_ch` independently rather than chaining
    // one method's output into the next. Chaining the .run() calls with `|` would
    // make Nextflow treat each method as dependent on the previous one's output
    // channel, forcing them to run sequentially per sample — even though each only
    // reads the original preprocessed query. Forking the source channel into
    // separate branches removes that artificial dependency so the methods run
    // concurrently; the branches are re-synchronized below.

    // CellTypist: two mutually-exclusive branches chained on one channel — only
    // one runs per sample (via runIf), producing a single celltypist_output.
    celltypist_ch = integration_ch
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
          "sanitize_ensembl_ids": "sanitize_ensembl_ids",
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
          "reference_var_gene_names": "reference_var_gene_names",
          "reference_var_input": "reference_var_input",
          "sanitize_ensembl_ids": "sanitize_ensembl_ids",
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

    harmony_knn_ch = integration_ch
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

    scanvi_scarches_ch = integration_ch
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
          "sanitize_ensembl_ids": "sanitize_ensembl_ids",
          "input_obs_categorical_covariate": "input_obs_categorical_covariates",
          "input_obs_continuous_covariate": "input_obs_numerical_covariates",
          "reference_obs_categorical_covariate": "reference_obs_categorical_covariates",
          "reference_obs_continuous_covariate": "reference_obs_numerical_covariates",
          "early_stopping": "scvi_early_stopping",
          "early_stopping_monitor": "scvi_early_stopping_monitor",
          "early_stopping_patience": "scvi_early_stopping_patience",
          "early_stopping_min_delta": "scvi_early_stopping_min_delta",
          "max_epochs": "scvi_max_epochs",
          "reduce_lr_on_plateau": "scvi_reduce_lr_on_plateau",
          "lr_factor": "scvi_lr_factor",
          "lr_patience": "scvi_lr_patience",
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

    scvi_knn_ch = integration_ch
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
          "sanitize_ensembl_ids": "sanitize_ensembl_ids",
          // scvi_knn re-exposes scVI training hparams under a `scvi_` prefix.
          "scvi_early_stopping": "scvi_early_stopping",
          "scvi_early_stopping_monitor": "scvi_early_stopping_monitor",
          "scvi_early_stopping_patience": "scvi_early_stopping_patience",
          "scvi_early_stopping_min_delta": "scvi_early_stopping_min_delta",
          "scvi_max_epochs": "scvi_max_epochs",
          "scvi_reduce_lr_on_plateau": "scvi_reduce_lr_on_plateau",
          "scvi_lr_factor": "scvi_lr_factor",
          "scvi_lr_patience": "scvi_lr_patience",
          "leiden_resolution": "leiden_resolution",
          "knn_weights": "knn_weights",
          "knn_n_neighbors": "knn_n_neighbors",
          "output_obs_predictions": "scvi_knn_obs_predictions",
          "output_obs_probability": "scvi_knn_obs_probability",
          "output_obsm_integrated": "scvi_knn_obsm_integrated"
        ],
        toState: ["scvi_knn_output": "output"]
      )

    singler_ch = integration_ch
    | singler_annotation.run(
        runIf: { id, state -> state.annotation_methods.contains("singler") },
        fromState: [
          "input": "input",
          "modality": "modality",
          // SingleR annotates on log-normalized counts.
          "input_layer": "input_layer_lognormalized",
          "input_var_gene_names": "input_var_gene_names",
          "input_reference_gene_overlap": "input_reference_gene_overlap",
          "reference": "reference",
          "reference_layer": "reference_layer_lognormalized",
          "reference_obs_target": "reference_obs_target",
          "reference_var_gene_names": "reference_var_gene_names",
          "reference_var_input": "reference_var_input",
          "input_obs_clusters": "singler_input_obs_clusters",
          "de_method": "singler_de_method",
          "de_n_genes": "singler_de_n_genes",
          "quantile": "singler_quantile",
          "fine_tune": "singler_fine_tune",
          "fine_tuning_threshold": "singler_fine_tuning_threshold",
          "prune": "singler_prune",
          "sanitize_ensembl_ids": "sanitize_ensembl_ids",
          "output_obs_predictions": "singler_obs_predictions",
          "output_obs_probability": "singler_obs_probability",
          "output_obs_delta_next": "singler_obs_delta_next",
          "output_obs_pruned_predictions": "singler_obs_pruned_predictions",
          "output_obsm_scores": "singler_obsm_scores"
        ],
        toState: ["singler_output": "output"]
      )

    // === Synchronize the parallel branches ===
    // Each branch emits one [id, state] per sample, carrying the shared base
    // parameters plus that branch's own "*_output" key. Mixing the four branches
    // and grouping by id brings them back into a single state. Outputs are picked
    // explicitly per branch rather than via a blind state merge, so a branch that
    // did not produce an output cannot clobber another's. A method skipped via
    // runIf still passes its event through, so the group size is always 4.
    synced_ch = celltypist_ch
    .mix(harmony_knn_ch, scanvi_scarches_ch, scvi_knn_ch, singler_ch)
    .groupTuple(by: 0, size: 5)
    .map { id, states ->
        def merged_state = states[0] + [
          "celltypist_output": states.collect { s -> s.celltypist_output }.find { v -> v != null },
          "harmony_knn_output": states.collect { s -> s.harmony_knn_output }.find { v -> v != null },
          "scanvi_scarches_output": states.collect { s -> s.scanvi_scarches_output }.find { v -> v != null },
          "scanvi_scarches_model": states.collect { s -> s.scanvi_scarches_model }.find { v -> v != null },
          "scvi_knn_output": states.collect { s -> s.scvi_knn_output }.find { v -> v != null },
          "singler_output": states.collect { s -> s.singler_output }.find { v -> v != null }
        ]
        [id, merged_state]
      }

    // === Sequential merge of per-method annotations ===
    // Each move_slots call depends on state.merged from the previous one, so
    // these run in order. move_anndata_slots copies the specified slots from
    // the method's output h5mu into the running merged target.
    output_ch = synced_ch
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
    | move_slots.run(
        key: "move_singler_slots",
        runIf: { id, state -> state.annotation_methods.contains("singler") },
        fromState: { id, state ->
          def singler_obs = [
            state.singler_obs_predictions,
            state.singler_obs_probability,
            state.singler_obs_delta_next
          ]
          // The pruned-predictions slot is only produced when pruning is enabled.
          if (state.singler_prune) {
            singler_obs << state.singler_obs_pruned_predictions
          }
          [
            "input_source": state.singler_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": singler_obs,
            "obsm": [state.singler_obsm_scores],
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

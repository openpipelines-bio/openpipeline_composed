workflow run_wf {
  take:
    input_ch

  main:
    // === Split modalities ===
    // Preserve the user-requested target modality and the original sample id
    // (both are needed after the channel is fanned out), then split the
    // (possibly multimodal) input into one h5mu file per modality.
    modalities_ch = input_ch
    | map { id, state ->
        def new_state = state + [
          "target_modality": state.modality,
          "original_id": id,
          "_meta": ["join_id": id]
        ]
        [id, new_state]
      }
    | split_modalities.run(
        fromState: [
          "input": "input",
          "output_compression": "output_compression"
        ],
        toState: [
          "split_modalities_output": "output",
          "split_modalities_types": "output_types"
        ]
      )
    // Fan the modality directory out into one event per modality, reading the
    // output_types csv (one row per modality file: columns `name`, `filename`).
    // Each event gets a modality-unique id so it can be run through components.
    | flatMap { id, state ->
        def outputDir = state.split_modalities_output
        def csv = state.split_modalities_types
          .splitCsv(strip: true, sep: ",")
          .findAll { !it[0].startsWith("#") }
        def header = csv.head()
        def rows = csv.tail().collect { row -> [header, row].transpose().collectEntries() }
        rows.collect { dat ->
          def new_id = "${state.original_id}_${dat.name}"
          def new_state = state + [
            "input": outputDir.resolve(dat.filename),
            "modality": dat.name
          ]
          [new_id, new_state]
        }
      }
    | map { id, state ->
        def keysToRemove = ["split_modalities_output", "split_modalities_types"]
        [id, state.findAll { it.key !in keysToRemove }]
      }

    // Only the target modality is subtyped; other modalities pass through
    // unaltered and are merged back at the end.
    target_ch = modalities_ch
    | filter { id, state -> state.modality == state.target_modality }

    passthrough_ch = modalities_ch
    | filter { id, state -> state.modality != state.target_modality }

    // === Subtype the target modality ===
    // Split the target modality by major cell type, run parallel annotation on
    // each per-cell-type file, then concatenate the subtyped files back into a
    // single unimodal file per (sample, modality).
    per_cell_type_ch = target_ch
    | split_h5mu.run(
        fromState: [
          "input": "input",
          "modality": "modality",
          "obs_feature": "obs_major_cell_type",
          "output_compression": "output_compression"
        ],
        // Cell-type names can collide after sanitizing; keep filenames unique.
        args: ["ensure_unique_filenames": true],
        toState: [
          "split_h5mu_output": "output",
          "split_h5mu_files": "output_files"
        ]
      )
    // When the reference carries a matching major cell-type annotation, split
    // it the same way (target modality only) so each major cell type can be
    // subtyped against the reference cells of that same type. These subsets are
    // only consumed by parallel_annotation below and are not part of the output.
    | split_h5mu.run(
        key: "split_reference_h5mu",
        runIf: { id, state -> state.reference != null && state.reference_obs_major_cell_type != null },
        fromState: [
          "input": "reference",
          "modality": "modality",
          "obs_feature": "reference_obs_major_cell_type",
          "output_compression": "output_compression"
        ],
        args: ["ensure_unique_filenames": true],
        toState: [
          "split_reference_output": "output",
          "split_reference_files": "output_files"
        ]
      )
    // Fan out into one event per major cell type (csv columns `name`,
    // `filename`). Keep the modality-level id as the group key so the subsets
    // can be concatenated back together after annotation.
    | flatMap { id, state ->
        def outputDir = state.split_h5mu_output
        def csv = state.split_h5mu_files
          .splitCsv(strip: true, sep: ",")
          .findAll { !it[0].startsWith("#") }
        def header = csv.head()
        def rows = csv.tail().collect { row -> [header, row].transpose().collectEntries() }

        // Map each major cell-type name to its reference subset (when the
        // reference was split by major cell type).
        def refByCellType = [:]
        def referenceWasSplit = state.split_reference_output != null
        if (referenceWasSplit) {
          def refDir = state.split_reference_output
          def refCsv = state.split_reference_files
            .splitCsv(strip: true, sep: ",")
            .findAll { !it[0].startsWith("#") }
          def refHeader = refCsv.head()
          refCsv.tail()
            .collect { row -> [refHeader, row].transpose().collectEntries() }
            .each { refByCellType[it.name] = refDir.resolve(it.filename) }
        }

        rows.collect { dat ->
          def new_id = "${id}_${dat.name}"

          // Match the query major cell type to its reference subset. When the
          // reference is not split by major cell type, every cell type is
          // subtyped against the full reference (or a pretrained model). When it
          // is split, a query cell type absent from the reference either errors
          // or, with --allow_missing_reference_cell_type, is passed through
          // unannotated.
          def reference = state.reference
          def annotate = true
          if (referenceWasSplit) {
            if (refByCellType.containsKey(dat.name)) {
              reference = refByCellType[dat.name]
            } else if (state.allow_missing_reference_cell_type) {
              annotate = false
            } else {
              throw new RuntimeException(
                "Major cell type '${dat.name}' has no matching subset in the " +
                "reference (--reference_obs_major_cell_type). Set " +
                "--allow_missing_reference_cell_type to true to pass such cell " +
                "types through without subtyping instead."
              )
            }
          }

          def new_state = state + [
            "id": new_id,
            "input": outputDir.resolve(dat.filename),
            "subtype_group_id": id,
            "major_cell_type": dat.name,
            "reference": reference,
            "annotate": annotate
          ]
          [new_id, new_state]
        }
      }
    | map { id, state ->
        def keysToRemove = ["split_h5mu_output", "split_h5mu_files", "split_reference_output", "split_reference_files"]
        [id, state.findAll { it.key !in keysToRemove }]
      }

    // Cell types with a matching reference (or, when the reference is not split
    // by major cell type, all cell types) are subtyped by parallel_annotation.
    annotated_ch = per_cell_type_ch
    | filter { id, state -> state.annotate }
    // Derive the predicted-label / probability .obs column names from the
    // reference target so subtype predictions are tagged with the label set
    // they were transferred from. Explicitly provided names take precedence;
    // the suffix is omitted when no reference target is set.
    | map { id, state ->
        def suffix = state.reference_obs_target ? "_${state.reference_obs_target}" : ""
        def slot_defaults = [
          "celltypist_obs_predictions": "celltypist_pred${suffix}",
          "celltypist_obs_probability": "celltypist_probability${suffix}",
          "harmony_knn_obs_predictions": "harmony_knn_pred${suffix}",
          "harmony_knn_obs_probability": "harmony_knn_probability${suffix}",
          "scanvi_scarches_obs_predictions": "scanvi_pred${suffix}",
          "scanvi_scarches_obs_probability": "scanvi_probability${suffix}",
          "scvi_knn_obs_predictions": "scvi_knn_pred${suffix}",
          "scvi_knn_obs_probability": "scvi_knn_probability${suffix}",
          "singler_obs_predictions": "singler_pred${suffix}",
          "singler_obs_probability": "singler_probability${suffix}",
          "singler_obs_delta_next": "singler_delta_next${suffix}",
          "singler_obs_pruned_predictions": "singler_pruned_labels${suffix}",
          "singler_obsm_scores": "singler_scores${suffix}",
          "consensus_obs_predictions": "consensus_pred${suffix}",
          "consensus_obs_score": "consensus_score${suffix}"
        ]
        def filled = slot_defaults.collectEntries { k, v -> [(k): state[k] ?: v] }
        [id, state + filled]
      }
    | parallel_annotation.run(
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "input_layer": "input_layer",
          "input_layer_lognormalized": "input_layer_lognormalized",
          "input_obs_batch_label": "input_obs_batch_label",
          "input_var_gene_names": "input_var_gene_names",
          "input_reference_gene_overlap": "input_reference_gene_overlap",
          "sanitize_ensembl_ids": "sanitize_ensembl_ids",
          "input_obs_categorical_covariates": "input_obs_categorical_covariates",
          "input_obs_numerical_covariates": "input_obs_numerical_covariates",
          "annotation_methods": "annotation_methods",
          "reference": "reference",
          "reference_layer": "reference_layer",
          "reference_layer_lognormalized": "reference_layer_lognormalized",
          "reference_obs_target": "reference_obs_target",
          "reference_obs_batch_label": "reference_obs_batch_label",
          "reference_var_gene_names": "reference_var_gene_names",
          "reference_var_input": "reference_var_input",
          "reference_obs_categorical_covariates": "reference_obs_categorical_covariates",
          "reference_obs_numerical_covariates": "reference_obs_numerical_covariates",
          "reference_obs_label_unlabeled_category": "reference_obs_label_unlabeled_category",
          "leiden_resolution": "leiden_resolution",
          "knn_weights": "knn_weights",
          "knn_n_neighbors": "knn_n_neighbors",
          "scvi_early_stopping": "scvi_early_stopping",
          "scvi_early_stopping_monitor": "scvi_early_stopping_monitor",
          "scvi_early_stopping_patience": "scvi_early_stopping_patience",
          "scvi_early_stopping_min_delta": "scvi_early_stopping_min_delta",
          "scvi_max_epochs": "scvi_max_epochs",
          "scvi_reduce_lr_on_plateau": "scvi_reduce_lr_on_plateau",
          "scvi_lr_factor": "scvi_lr_factor",
          "scvi_lr_patience": "scvi_lr_patience",
          "celltypist_model": "celltypist_model",
          "celltypist_majority_voting": "celltypist_majority_voting",
          "celltypist_feature_selection": "celltypist_feature_selection",
          "celltypist_C": "celltypist_C",
          "celltypist_max_iter": "celltypist_max_iter",
          "celltypist_use_SGD": "celltypist_use_SGD",
          "celltypist_min_prop": "celltypist_min_prop",
          "harmony_knn_n_hvg": "harmony_knn_n_hvg",
          "harmony_knn_pca_num_components": "harmony_knn_pca_num_components",
          "harmony_knn_theta": "harmony_knn_theta",
          "scvi_knn_n_hvg": "scvi_knn_n_hvg",
          "singler_input_obs_clusters": "singler_input_obs_clusters",
          "singler_de_method": "singler_de_method",
          "singler_de_n_genes": "singler_de_n_genes",
          "singler_quantile": "singler_quantile",
          "singler_fine_tune": "singler_fine_tune",
          "singler_fine_tuning_threshold": "singler_fine_tuning_threshold",
          "singler_prune": "singler_prune",
          "celltypist_obs_predictions": "celltypist_obs_predictions",
          "celltypist_obs_probability": "celltypist_obs_probability",
          "harmony_knn_obs_predictions": "harmony_knn_obs_predictions",
          "harmony_knn_obs_probability": "harmony_knn_obs_probability",
          "harmony_knn_obsm_integrated": "harmony_knn_obsm_integrated",
          "scanvi_scarches_obs_predictions": "scanvi_scarches_obs_predictions",
          "scanvi_scarches_obs_probability": "scanvi_scarches_obs_probability",
          "scanvi_scarches_obsm_integrated": "scanvi_scarches_obsm_integrated",
          "scvi_knn_obs_predictions": "scvi_knn_obs_predictions",
          "scvi_knn_obs_probability": "scvi_knn_obs_probability",
          "scvi_knn_obsm_integrated": "scvi_knn_obsm_integrated",
          "singler_obs_predictions": "singler_obs_predictions",
          "singler_obs_probability": "singler_obs_probability",
          "singler_obs_delta_next": "singler_obs_delta_next",
          "singler_obs_pruned_predictions": "singler_obs_pruned_predictions",
          "singler_obsm_scores": "singler_obsm_scores",
          "run_consensus": "run_consensus",
          "consensus_obs_predictions": "consensus_obs_predictions",
          "consensus_obs_score": "consensus_obs_score",
          "consensus_use_probabilities": "consensus_use_probabilities",
          "consensus_tie_label": "consensus_tie_label",
          "output_compression": "output_compression"
        ],
        toState: ["input": "output"]
      )

    // Cell types absent from the split reference are passed through unannotated
    // (only reached when --allow_missing_reference_cell_type is set); their
    // per-cell-type subset file flows straight to concatenation.
    passthrough_cell_types_ch = per_cell_type_ch
    | filter { id, state -> !state.annotate }

    // Concatenate the per-cell-type subsets back into one unimodal file. The
    // subsets hold disjoint observations, so concatenation restores the full
    // set of cells for the modality.
    subtyped_ch = annotated_ch.mix(passthrough_cell_types_ch)
    | map { id, state -> [state.subtype_group_id, id, state] }
    | groupTuple(by: 0, sort: "hash")
    | map { group_id, cell_type_ids, states ->
        // Every non per-cell-type key is identical across the subsets (they all
        // originate from the same modality file), so carry the first state.
        def merged_state = states[0] + [
          "input": states.collect { it.input },
          "input_id": cell_type_ids
        ]
        [group_id, merged_state]
      }
    | concatenate_h5mu.run(
        fromState: [
          "input": "input",
          "input_id": "input_id",
          "modality": "modality",
          "output_compression": "output_compression"
        ],
        toState: ["input": "output"]
      )

    // === Merge modalities back together ===
    // Group the subtyped target modality with the untouched passthrough
    // modalities per original sample, then merge them into one output h5mu.
    output_ch = subtyped_ch.mix(passthrough_ch)
    | map { id, state -> [state.original_id, state] }
    | groupTuple(by: 0, sort: "hash")
    | map { orig_id, states ->
        def merged_state = states[0] + [
          "input": states.collect { it.input }
        ]
        [orig_id, merged_state]
      }
    | merge.run(
        fromState: [
          "input": "input",
          "output_compression": "output_compression"
        ],
        toState: ["output": "output"]
      )
    | setState(["output", "_meta"])

  emit:
    output_ch
}

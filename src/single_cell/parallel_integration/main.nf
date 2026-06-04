// Helper: build the list of .obs cluster column names a leiden-based workflow
// will produce, given the prefix and the list of resolutions.
// Openpipeline's workflows name each column "{obs_cluster_prefix}_{resolution}"
// where the resolution is formatted as Python's str(float) (e.g. "1.0").
def leidenObsColumns(prefix, resolutions) {
  resolutions.collect { r ->
    def s = (r instanceof Number) ? (r as Double).toString() : r.toString()
    "${prefix}_${s}"
  }
}

workflow run_wf {
  take:
    input_ch

  main:
    integration_ch = input_ch
    // === Validate method-specific requirements ===
    // Fail (or warn) early when a selected method's required input layer is
    // missing, rather than surfacing the error deep inside a sub-workflow.
    | map { id, state ->
        if (state.integration_methods.contains("scvi") && !state.layer_raw_counts) {
          System.err.println(
            "Warning: scVI was selected but --layer_raw_counts is not set; scVI " +
            "will read raw counts from the '${state.modality}' modality's .X."
          )
        }
        def lognorm_methods = state.integration_methods.findAll { method ->
          method in ["harmony", "scanorama", "bbknn"]
        }
        if (lognorm_methods && !state.layer_log_normalized_counts) {
          throw new RuntimeException(
            "Methods ${lognorm_methods} require log-normalized counts, but " +
            "--layer_log_normalized_counts is not set."
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

    // === Parallel integration runs ===
    // Each integration method reads from `integration_ch` independently rather
    // than chaining one method's output into the next. Chaining the .run() calls
    // with `|` would make Nextflow treat each method as dependent on the previous
    // one's output channel, forcing them to run sequentially per sample — even
    // though each only reads the original preprocessed input. Forking the source
    // channel into separate branches removes that artificial dependency so the
    // methods run concurrently; the branches are re-synchronized below.
    harmony_ch = integration_ch
    | harmony_integration.run(
        runIf: { id, state -> state.integration_methods.contains("harmony") },
        fromState: [
          "input": "input",
          "modality": "modality",
          "layer": "layer_log_normalized_counts",
          "embedding": "obsm_embedding",
          "obs_covariates": "obs_covariates",
          "theta": "harmony_theta",
          "leiden_resolution": "leiden_resolution",
          "obsm_integrated": "harmony_obsm_integrated",
          "obsm_umap": "harmony_obsm_umap",
          "obs_cluster": "harmony_obs_cluster",
          "uns_neighbors": "harmony_uns_neighbors",
          "obsp_neighbor_distances": "harmony_obsp_neighbor_distances",
          "obsp_neighbor_connectivities": "harmony_obsp_neighbor_connectivities"
        ],
        toState: ["harmony_output": "output"]
      )

    scvi_ch = integration_ch
    | scvi_integration.run(
        runIf: { id, state -> state.integration_methods.contains("scvi") },
        fromState: [
          "input": "input",
          "modality": "modality",
          // scVI trains on raw counts, not the log-normalized layer the other
          // methods use; layer_raw_counts defaults to unset so scVI reads .X.
          "layer": "layer_raw_counts",
          "obs_batch": "obs_batch",
          "obs_categorical_covariate": "obs_categorical_covariates",
          "obs_continuous_covariate": "obs_numerical_covariates",
          "var_input": "var_input",
          "leiden_resolution": "leiden_resolution",
          "early_stopping": "scvi_early_stopping",
          "early_stopping_monitor": "scvi_early_stopping_monitor",
          "early_stopping_patience": "scvi_early_stopping_patience",
          "early_stopping_min_delta": "scvi_early_stopping_min_delta",
          "max_epochs": "scvi_max_epochs",
          "reduce_lr_on_plateau": "scvi_reduce_lr_on_plateau",
          "lr_factor": "scvi_lr_factor",
          "lr_patience": "scvi_lr_patience",
          "obsm_output": "scvi_obsm_integrated",
          "obsm_umap": "scvi_obsm_umap",
          "obs_cluster": "scvi_obs_cluster",
          "uns_neighbors": "scvi_uns_neighbors",
          "obsp_neighbor_distances": "scvi_obsp_neighbor_distances",
          "obsp_neighbor_connectivities": "scvi_obsp_neighbor_connectivities"
        ],
        toState: [
          "scvi_output": "output",
          "scvi_model": "output_model"
        ]
      )

    scanorama_ch = integration_ch
    | scanorama_integration.run(
        runIf: { id, state -> state.integration_methods.contains("scanorama") },
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "layer": "layer_log_normalized_counts",
          "obs_batch": "obs_batch",
          "obsm_input": "obsm_embedding",
          "knn": "scanorama_knn",
          "batch_size": "scanorama_batch_size",
          "sigma": "scanorama_sigma",
          "approx": "scanorama_approx",
          "alpha": "scanorama_alpha",
          "leiden_resolution": "leiden_resolution",
          "obsm_output": "scanorama_obsm_integrated",
          "obsm_umap": "scanorama_obsm_umap",
          "obs_cluster": "scanorama_obs_cluster",
          "uns_neighbors": "scanorama_uns_neighbors",
          "obsp_neighbor_distances": "scanorama_obsp_neighbor_distances",
          "obsp_neighbor_connectivities": "scanorama_obsp_neighbor_connectivities"
        ],
        toState: ["scanorama_output": "output"]
      )

    bbknn_ch = integration_ch
    | bbknn_integration.run(
        runIf: { id, state -> state.integration_methods.contains("bbknn") },
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "layer": "layer_log_normalized_counts",
          "obsm_input": "obsm_embedding",
          "obs_batch": "obs_batch",
          "n_neighbors_within_batch": "bbknn_n_neighbors_within_batch",
          "n_pcs": "bbknn_n_pcs",
          "n_trim": "bbknn_n_trim",
          "leiden_resolution": "leiden_resolution",
          "obsm_umap": "bbknn_obsm_umap",
          "obs_cluster": "bbknn_obs_cluster",
          "uns_output": "bbknn_uns_neighbors",
          "obsp_distances": "bbknn_obsp_neighbor_distances",
          "obsp_connectivities": "bbknn_obsp_neighbor_connectivities"
        ],
        toState: ["bbknn_output": "output"]
      )

    // === Synchronize the parallel branches ===
    // Each branch emits one [id, state] per sample; every state carries the
    // shared base parameters plus that branch's own "*_output" key. Mixing the
    // four branches and grouping by id brings all four back into a single state.
    // Outputs are picked explicitly per branch rather than via a blind state
    // merge, so a branch that did not produce an output cannot clobber another
    // branch's real path. A method skipped via runIf still passes its event
    // through unchanged, so the group size is always 4 and its "*_output" is
    // simply absent (resolved to null here and gated again at the merge below).
    synced_ch = harmony_ch
    .mix(scvi_ch, scanorama_ch, bbknn_ch)
    .groupTuple(by: 0, size: 4)
    .map { id, states ->
        def merged_state = states[0] + [
          "harmony_output": states.collect { s -> s.harmony_output }.find { v -> v != null },
          "scvi_output": states.collect { s -> s.scvi_output }.find { v -> v != null },
          "scanorama_output": states.collect { s -> s.scanorama_output }.find { v -> v != null },
          "bbknn_output": states.collect { s -> s.bbknn_output }.find { v -> v != null },
          "scvi_model": states.collect { s -> s.scvi_model }.find { v -> v != null }
        ]
        [id, merged_state]
      }

    // === Sequential merge of per-method annotations ===
    // Each move_slots call depends on state.merged from the previous one, so
    // these run in order. move_anndata_slots copies the specified slots from
    // the method's output h5mu into the running merged target.
    output_ch = synced_ch
    | move_slots.run(
        key: "move_harmony_slots",
        runIf: { id, state -> state.integration_methods.contains("harmony") },
        fromState: { id, state ->
          [
            "input_source": state.harmony_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": leidenObsColumns(state.harmony_obs_cluster, state.leiden_resolution),
            "obsm": [state.harmony_obsm_integrated, state.harmony_obsm_umap],
            "obsp": [
              state.harmony_obsp_neighbor_distances,
              state.harmony_obsp_neighbor_connectivities
            ],
            "uns": [state.harmony_uns_neighbors],
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )
    | move_slots.run(
        key: "move_scvi_slots",
        runIf: { id, state -> state.integration_methods.contains("scvi") },
        fromState: { id, state ->
          [
            "input_source": state.scvi_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": leidenObsColumns(state.scvi_obs_cluster, state.leiden_resolution),
            "obsm": [state.scvi_obsm_integrated, state.scvi_obsm_umap],
            "obsp": [
              state.scvi_obsp_neighbor_distances,
              state.scvi_obsp_neighbor_connectivities
            ],
            "uns": [state.scvi_uns_neighbors],
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )
    | move_slots.run(
        key: "move_scanorama_slots",
        runIf: { id, state -> state.integration_methods.contains("scanorama") },
        fromState: { id, state ->
          [
            "input_source": state.scanorama_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": leidenObsColumns(state.scanorama_obs_cluster, state.leiden_resolution),
            "obsm": [state.scanorama_obsm_integrated, state.scanorama_obsm_umap],
            "obsp": [
              state.scanorama_obsp_neighbor_distances,
              state.scanorama_obsp_neighbor_connectivities
            ],
            "uns": [state.scanorama_uns_neighbors],
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )
    | move_slots.run(
        key: "move_bbknn_slots",
        runIf: { id, state -> state.integration_methods.contains("bbknn") },
        fromState: { id, state ->
          [
            "input_source": state.bbknn_output,
            "input_target": state.merged,
            "source_modality": state.modality,
            "target_modality": state.modality,
            "obs": leidenObsColumns(state.bbknn_obs_cluster, state.leiden_resolution),
            // bbknn does not produce an integration embedding of its own,
            // only a UMAP derived from the batch-aware graph.
            "obsm": [state.bbknn_obsm_umap],
            "obsp": [
              state.bbknn_obsp_neighbor_distances,
              state.bbknn_obsp_neighbor_connectivities
            ],
            "uns": [state.bbknn_uns_neighbors],
            "allow_overwrite": true,
            "output_compression": state.output_compression
          ]
        },
        toState: ["merged": "output"]
      )

    | map { id, state ->
        def out = ["output": state.merged]
        // scvi_model is only present when scVI was among the selected methods.
        if (state.scvi_model) {
          out["output_scvi_model"] = state.scvi_model
        }
        [id, state + out]
      }
    | setState(["output", "output_scvi_model", "_meta"])

  emit:
    output_ch
}

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
    output_ch = input_ch
    | map { id, state ->
        def new_state = state + [
          "merged": state.input,
          "_meta": ["join_id": id]
        ]
        [id, new_state]
      }

    // === Parallel integration runs ===
    // Each .run() below reads state.input (the ORIGINAL preprocessed file),
    // NOT the previous step's output. Nextflow's DAG scheduler therefore sees
    // no dependency between these calls and executes them concurrently.
    | harmony_integration.run(
        runIf: { id, state -> state.integration_methods.contains("harmony") },
        fromState: [
          "input": "input",
          "modality": "modality",
          "layer": "layer",
          "embedding": "obsm_embedding",
          "obs_covariates": "harmony_obs_covariates",
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
    | scvi_integration.run(
        runIf: { id, state -> state.integration_methods.contains("scvi") },
        fromState: [
          "input": "input",
          "modality": "modality",
          "layer": "layer",
          "obs_batch": "scvi_obs_batch",
          "var_input": "scvi_var_input",
          "leiden_resolution": "leiden_resolution",
          "early_stopping": "early_stopping",
          "early_stopping_monitor": "early_stopping_monitor",
          "early_stopping_patience": "early_stopping_patience",
          "early_stopping_min_delta": "early_stopping_min_delta",
          "max_epochs": "max_epochs",
          "reduce_lr_on_plateau": "reduce_lr_on_plateau",
          "lr_factor": "lr_factor",
          "lr_patience": "lr_patience",
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
    | scanorama_integration.run(
        runIf: { id, state -> state.integration_methods.contains("scanorama") },
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "layer": "layer",
          "obs_batch": "scanorama_obs_batch",
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
    | bbknn_integration.run(
        runIf: { id, state -> state.integration_methods.contains("bbknn") },
        fromState: [
          "id": "id",
          "input": "input",
          "modality": "modality",
          "layer": "layer",
          "obsm_input": "obsm_embedding",
          "obs_batch": "bbknn_obs_batch",
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

    // === Sequential merge of per-method annotations ===
    // Each move_slots call depends on state.merged from the previous one, so
    // these run in order. move_anndata_slots copies the specified slots from
    // the method's output h5mu into the running merged target.
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
        [id, state + ["output": state.merged]]
      }
    | setState(["output", "_meta"])

  emit:
    output_ch
}

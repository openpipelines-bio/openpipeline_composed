workflow run_wf {
  take:
    input_ch

  main:
    output_ch = input_ch
    | map { id, state ->
      def new_state = state + [ "workflouw_output": state.output, "_meta": ["join_id": id] ]
      [id, new_state]
    }

    | harmony_integration.run(
      runIf: { id, state -> 
        state.integration_methods.contains("harmony") 
      },
      fromState: [ 
        "id": "id",
        "input": "input",
        "modality": "modality",
        "layer": "layer",
        "theta": "harmony_theta",
        "leiden_resolution": "leiden_resolution",
        "obs_covariates": "harmony_obs_covariates",
        "embedding": "obsm_embedding",
        "obsm_integrated": "harmony_obsm_integrated",
        "uns_neighbors": "harmony_uns_neighbors",
        "obsp_neighbor_distances": "harmony_obsp_neighbor_distances",
        "obsp_neighbor_connectivities": "harmony_obsp_neighbor_connectivities",
        "obs_cluster": "harmony_obs_cluster",
        "obsm_umap": "harmony_obsm_umap"
      ],
      toState: [ "input": "output" ]
    )

    | scvi_integration.run(
      runIf: { id, state -> 
        state.integration_methods.contains("scvi")
      },
      fromState: [ 
        "id": "id",
        "input": "input",
        "layer": "input_layer",
        "obs_batch": "obs_batch",
        "var_input": "var_input",
        "modality": "modality",
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
        "uns_neighbors": "scvi_integration_neighbors",
        "obsp_neighbor_distances": "scvi_obsp_neighbor_distances",
        "obsp_neighbor_connectivities": "scvi_obsp_neighbor_connectivities",
        "obs_cluster": "scvi_obs_cluster",
        "obsm_umap": "scvi_obsm_umap"
      ],
      toState: [ "input": "output", "scvi_model": "output_model" ]
    )

    | map {id, state ->
      def new_state = state + ["output": state.query_processed]
      [id, new_state]
    }

    | setState(["output", "_meta"])

  emit:
    output_ch
}
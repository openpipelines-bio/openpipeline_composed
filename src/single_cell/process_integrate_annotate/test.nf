nextflow.enable.dsl=2

include { process_integrate_annotate } from params.rootDir + "/target/nextflow/single_cell/process_integrate_annotate/main.nf"
include { assert_h5mu_slots } from params.rootDir + "/target/_test/nextflow/test_workflows/assert_h5mu_slots/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_incubator/resources_test/"

// Expected integration slots written into the merged output, using the workflow's default slot names. 
def integrationSlots(methods) {
  def obs = [], obsm = [], obsp = [], uns = []
  (methods ?: []).each { method ->
    def prefix = "${method}_integration"
    obs << "${prefix}_leiden_1.0"
    obsm << "X_${method}_umap"
    if (method != "bbknn") obsm << "X_${method}_integrated"
    obsp << "${prefix}_neighbor_distances"
    obsp << "${prefix}_neighbor_connectivities"
    uns << "${prefix}_neighbors"
  }
  [obs: obs, obsm: obsm, obsp: obsp, uns: uns]
}

// Expected annotation slots written into the merged output.
def annotationSlots(methods) {
  def perMethod = [
    "celltypist":      [obs: ["celltypist_pred", "celltypist_probability"], obsm: []],
    "harmony_knn":     [obs: ["harmony_knn_pred", "harmony_knn_probability"], obsm: ["X_integrated_harmony"]],
    "scanvi_scarches": [obs: ["scanvi_pred", "scanvi_probability"], obsm: ["X_integrated_scanvi"]],
    "scvi_knn":        [obs: ["scvi_knn_pred", "scvi_knn_probability"], obsm: ["X_integrated_scvi"]],
    "singler":         [obs: ["singler_pred", "singler_probability", "singler_delta_next", "singler_pruned_labels"], obsm: ["singler_scores"]]
  ]
  def obs = [], obsm = []
  (methods ?: []).each { method ->
    obs += perMethod[method].obs
    obsm += perMethod[method].obsm
  }
  [obs: obs, obsm: obsm]
}

// Combine the integration and annotation expectations.
def expectedSlots(integration_methods, annotation_methods) {
  def i = integrationSlots(integration_methods)
  def a = annotationSlots(annotation_methods)
  [obs: i.obs + a.obs, obsm: i.obsm + a.obsm, obsp: i.obsp, uns: i.uns]
}


workflow test_wf {
  resources_test = file(params.resources_test)

  def integration_methods = ["harmony", "scvi", "scanorama", "bbknn"]
  def annotation_methods = ["celltypist", "harmony_knn", "scanvi_scarches", "scvi_knn", "singler"]

  output_ch = Channel.fromList(
    [
      [
        id: "all_methods_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        reference: resources_test.resolve("annotation_test_data/TS_Blood_filtered.h5mu"),
        reference_var_gene_names: "ensemblid",
        reference_var_input: "highly_variable",
        reference_layer_lognormalized_counts: "log_normalized",
        reference_obs_batch: "donor_assay",
        reference_obs_label: "cell_type",
        integration_methods: "harmony;scvi;scanorama;bbknn",
        annotation_methods: "celltypist;harmony_knn;scanvi_scarches;scvi_knn;singler",
        max_epochs: "5"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | process_integrate_annotate
    | view { "After AaaS: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "merged" : "Output ID should be `merged`. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      // scVI integration and scANVI/scArches annotation each emit a trained model.
      assert state.containsKey("output_scvi_model") : "Output should contain the trained scVI model."
      assert state.output_scvi_model.exists() : "'output_scvi_model' should exist."
      assert state.containsKey("output_scanvi_model") : "Output should contain the trained scANVI model."
      assert state.output_scanvi_model.exists() : "'output_scanvi_model' should exist."

      "Output: $output"
    }
    | assert_h5mu_slots.run(
        fromState: { id, state ->
          def slots = expectedSlots(integration_methods, annotation_methods)
          // Multiple annotation methods selected, so the consensus_vote step runs
          // and adds a consensus prediction and score.
          def obs = slots.obs + ["consensus_pred", "consensus_score"]
          [
            "input": state.output,
            "modality": "rna",
            "obs": obs,
            "obsm": slots.obsm,
            "obsp": slots.obsp,
            "uns": slots.uns
          ]
        }
      )

  // Ensure the case actually ran through the assert step; without this a run that
  // emits no events would silently pass.
  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 1 :
          "output channel should contain 1 event, found ${output_list.size()}"
      }
}

// Integration-only run (no annotation methods) with detailed pre-processing
// parameters. Confirms the annotation step is gated off, the integration slots
// and the scVI model are produced, and no scANVI model is emitted.
workflow test_wf_2 {
  resources_test = file(params.resources_test)

  def integration_methods = ["harmony", "scvi", "scanorama", "bbknn"]

  output_ch = Channel.fromList(
    [
      [
        id: "integration_only_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        rna_min_counts: 2,
        rna_max_counts: 1000000,
        rna_min_genes_per_cell: 1,
        rna_max_genes_per_cell: 1000000,
        rna_min_cells_per_gene: 1,
        rna_min_fraction_mito: 0.0,
        rna_max_fraction_mito: 1.0,
        rna_min_fraction_ribo: 0.0,
        rna_max_fraction_ribo: 1.0,
        var_name_mitochondrial_genes: 'mitochondrial',
        var_name_ribosomal_genes: 'ribosomal',
        obs_name_mitochondrial_fraction: 'fraction_mitochondrial',
        obs_name_ribosomal_fraction: 'fraction_ribosomal',
        integration_methods: "harmony;scvi;scanorama;bbknn",
        max_epochs: "5"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | process_integrate_annotate
    | view { "After AaaS: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "merged" : "Output ID should be `merged`. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      // scVI was selected, so its model is emitted; no annotation ran, so the
      // scANVI model must be absent.
      assert state.containsKey("output_scvi_model") : "Output should contain the trained scVI model."
      assert state.output_scvi_model.exists() : "'output_scvi_model' should exist."
      assert !state.containsKey("output_scanvi_model") : "No scANVI model should be emitted when no annotation runs."

      "Output: $output"
    }
    | assert_h5mu_slots.run(
        fromState: { id, state ->
          def slots = expectedSlots(integration_methods, [])
          [
            "input": state.output,
            "modality": "rna",
            // The mito/ribo fraction obs columns are only written when the
            // obs_name_*_fraction arguments are wired through to process_samples.
            "obs": slots.obs + ["fraction_mitochondrial", "fraction_ribosomal"],
            "obsm": slots.obsm,
            "obsp": slots.obsp,
            "uns": slots.uns
          ]
        }
      )

  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 1 :
          "output channel should contain 1 event, found ${output_list.size()}"
      }
}

// Full pre-processing passthrough run. Exercises the multi-modality filters
// (RNA, protein/CITE-seq, GDO), cross-modality intersection, CLR, QC top_n_vars,
// mitochondrial/ribosomal detection with fraction outputs and the RNA scaling
// block — all forwarded to process_samples. A single integration method is used
// to keep the run cheap. Since VDSL3 .run() validates argument names against the
// process_samples config, this run failing on an unknown argument would flag any
// mis-wired pre-processing parameter; the slot assertions confirm the parameters
// that produce .obs/.obsm slots actually took effect.
workflow test_wf_4 {
  resources_test = file(params.resources_test)

  def integration_methods = ["harmony"]

  output_ch = Channel.fromList(
    [
      [
        id: "preprocessing_passthrough_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        input_var_gene_names: "gene_symbol",
        // RNA filtering (permissive so cells survive for integration)
        rna_min_counts: 2,
        rna_max_counts: 1000000,
        rna_min_genes_per_cell: 1,
        rna_max_genes_per_cell: 1000000,
        rna_min_cells_per_gene: 1,
        rna_min_fraction_mito: 0.0,
        rna_max_fraction_mito: 1.0,
        rna_min_fraction_ribo: 0.0,
        rna_max_fraction_ribo: 1.0,
        skip_scrublet_doublet_detection: true,
        // Protein (CITE-seq) filtering
        prot_min_counts: 1,
        prot_max_counts: 1000000,
        prot_min_proteins_per_cell: 1,
        prot_max_proteins_per_cell: 1000000,
        prot_min_cells_per_protein: 1,
        // GDO filtering (no GDO modality present; validates the arguments are wired)
        gdo_min_counts: 1,
        gdo_max_counts: 1000000,
        gdo_min_guides_per_cell: 1,
        gdo_max_guides_per_cell: 1000000,
        gdo_min_cells_per_guide: 1,
        // Cross-modality filtering
        intersect_obs: true,
        // Mitochondrial & ribosomal detection with fraction outputs
        var_name_mitochondrial_genes: 'mitochondrial',
        var_name_ribosomal_genes: 'ribosomal',
        obs_name_mitochondrial_fraction: 'fraction_mitochondrial',
        obs_name_ribosomal_fraction: 'fraction_ribosomal',
        // QC metrics
        top_n_vars: "20,50",
        // CLR (protein normalization)
        clr_axis: 1,
        // RNA scaling
        rna_enable_scaling: true,
        rna_scaling_max_value: 10.0,
        integration_methods: "harmony"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | process_integrate_annotate
    | view { "After AaaS: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "merged" : "Output ID should be `merged`. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      // Only harmony ran, so no scVI/scANVI models are emitted.
      assert !state.containsKey("output_scvi_model") : "No scVI model should be emitted when scvi integration is not run."
      assert !state.containsKey("output_scanvi_model") : "No scANVI model should be emitted when no annotation runs."

      "Output: $output"
    }
    | assert_h5mu_slots.run(
        fromState: { id, state ->
          def slots = expectedSlots(integration_methods, [])
          [
            "input": state.output,
            "modality": "rna",
            // Fraction columns come from obs_name_*_fraction; the scaled_pca /
            // scaled_umap embeddings come from the RNA scaling block.
            "obs": slots.obs + ["fraction_mitochondrial", "fraction_ribosomal"],
            "obsm": slots.obsm + ["scaled_pca", "scaled_umap"],
            "obsp": slots.obsp,
            "uns": slots.uns
          ]
        }
      )

  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 1 :
          "output channel should contain 1 event, found ${output_list.size()}"
      }
}

// Annotation-only run (no integration methods) exercising the celltypist
// pretrained-model branch. The Immune_All_Low model is keyed on gene symbols, so
// var names are gene symbols and ensembl sanitization is disabled. Confirms the
// integration step is gated off and no models are emitted.
workflow test_wf_3 {
  resources_test = file(params.resources_test)

  def annotation_methods = ["celltypist"]

  output_ch = Channel.fromList(
    [
      [
        id: "celltypist_model_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        celltypist_model: resources_test.resolve("annotation_test_data/celltypist_model_Immune_All_Low.pkl"),
        annotation_methods: "celltypist",
        input_var_gene_names: "gene_symbol",
        sanitize_ensembl_ids: false
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | process_integrate_annotate
    | view { "After AaaS: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "merged" : "Output ID should be `merged`. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      // No integration or scANVI annotation ran, so neither model is emitted.
      assert !state.containsKey("output_scvi_model") : "No scVI model should be emitted when no integration runs."
      assert !state.containsKey("output_scanvi_model") : "No scANVI model should be emitted when scanvi_scarches is not run."

      "Output: $output"
    }
    | assert_h5mu_slots.run(
        fromState: { id, state ->
          def slots = expectedSlots([], annotation_methods)
          ["input": state.output, "modality": "rna", "obs": slots.obs, "obsm": slots.obsm]
        }
      )

  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 1 :
          "output channel should contain 1 event, found ${output_list.size()}"
      }
}

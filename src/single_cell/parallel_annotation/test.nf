nextflow.enable.dsl=2

include { parallel_annotation } from params.rootDir + "/target/nextflow/single_cell/parallel_annotation/main.nf"
include { assert_h5mu_slots } from params.rootDir + "/target/_test/nextflow/test_workflows/assert_h5mu_slots/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_incubator/resources_test/"

// Default .obs prediction/probability and .obsm embedding slots each method
// writes into the merged output. celltypist produces predictions only.
def annotationSlots(methods) {
  def perMethod = [
    "celltypist":      [obs: ["celltypist_pred", "celltypist_probability"], obsm: []],
    "harmony_knn":     [obs: ["harmony_knn_pred", "harmony_knn_probability"], obsm: ["X_integrated_harmony"]],
    "scanvi_scarches": [obs: ["scanvi_pred", "scanvi_probabilities"], obsm: ["X_integrated_scanvi"]],
    "scvi_knn":        [obs: ["scvi_knn_pred", "scvi_knn_probability"], obsm: ["X_integrated_scvi"]]
  ]
  def obs = [], obsm = []
  methods.each { method ->
    obs += perMethod[method].obs
    obsm += perMethod[method].obsm
  }
  [obs: obs, obsm: obsm]
}

workflow test_wf {
  resources_test = file(params.resources_test)

  def methods = ["celltypist", "harmony_knn", "scanvi_scarches", "scvi_knn"]

  output_ch = Channel.fromList(
    [
      [
        id: "all_methods_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        input_layer_lognormalized: "log_normalized",
        input_obs_batch_label: "sample_id",
        reference: resources_test.resolve("annotation_test_data/TS_Blood_filtered.h5mu"),
        reference_layer_lognormalized: "log_normalized",
        reference_var_gene_names: "ensemblid",
        reference_obs_batch_label: "donor_assay",
        reference_obs_target: "cell_type",
        annotation_methods: "celltypist;harmony_knn;scanvi_scarches;scvi_knn",
        scvi_max_epochs: 5
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | parallel_annotation
    | view { "After parallel_annotation: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id.endsWith("_test") || id == "merged" : "Output ID should end with _test or be 'merged'. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      "Output: $output"
    }
    | assert_h5mu_slots.run(
        fromState: { id, state ->
          def slots = annotationSlots(methods)
          ["input": state.output, "modality": "rna", "obs": slots.obs, "obsm": slots.obsm]
        }
      )

  // Verify the test case actually ran through the assert step.
  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 1 :
          "output channel should contain 1 event, found ${output_list.size()}"
        assert output_list.collect { ev -> ev[0] } == ["all_methods_test"] :
          "expected the test case to complete; found ${output_list.collect { ev -> ev[0] }}"
      }
}

workflow test_wf_2 {
  // Exercise the celltypist "pretrained model" branch with a single method
  // selected, to confirm runIf gates short-circuit the other three.
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList(
    [
      [
        id: "celltypist_model_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        celltypist_model: resources_test.resolve("annotation_test_data/celltypist_model_Immune_All_Low.pkl"),
        input_var_gene_names: "gene_symbol",
        annotation_methods: "celltypist"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | parallel_annotation
    | view { "After parallel_annotation: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      "Output: $output"
    }
    | assert_h5mu_slots.run(
        fromState: { id, state ->
          def slots = annotationSlots(["celltypist"])
          ["input": state.output, "modality": "rna", "obs": slots.obs, "obsm": slots.obsm]
        }
      )

  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 1 :
          "output channel should contain 1 event, found ${output_list.size()}"
        assert output_list.collect { ev -> ev[0] } == ["celltypist_model_test"] :
          "expected the test case to complete; found ${output_list.collect { ev -> ev[0] }}"
      }
}

nextflow.enable.dsl=2

include { multi_annotation } from params.rootDir + "/target/nextflow/single_cell/multi_annotation/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_incubator/resources_test/"

workflow test_wf {
  resources_test = file(params.resources_test)

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
        max_epochs: 5
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | multi_annotation
    | view { "After multi_annotation: $it" }
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
    | multi_annotation
    | view { "After multi_annotation: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      "Output: $output"
    }
}

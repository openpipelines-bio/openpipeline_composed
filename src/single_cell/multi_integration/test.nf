nextflow.enable.dsl=2

include { multi_integration } from params.rootDir + "/target/nextflow/single_cell/multi_integration/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_incubator/resources_test/"

workflow test_wf {
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList(
    [
      [
        id: "all_methods_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        integration_methods: "harmony;scvi;scanorama;bbknn",
        harmony_obs_covariates: "sample_id",
        scvi_obs_batch: "sample_id",
        scanorama_obs_batch: "sample_id",
        bbknn_obs_batch: "sample_id",
        max_epochs: "5"
      ],
      [
        id: "single_method_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        integration_methods: "harmony",
        harmony_obs_covariates: "sample_id"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | multi_integration
    | view { "After multi_integration: $it" }
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

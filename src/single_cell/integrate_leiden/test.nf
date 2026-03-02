nextflow.enable.dsl=2

include { integrate_leiden } from params.rootDir + "/target/_private/nextflow/single_cell/integrate_leiden/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_incubator/resources_test/pbmc_1k_protein_v3/"

workflow test_wf {
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList(
    [
      [
        id: "simple_integration_test",
        input: resources_test.resolve("pbmc_1k_protein_v3_mms.h5mu"),
        obs_batch: "sample_id",
        integration_methods: "harmony;scvi"
      ]
    ])
    | view {"State at start: $it"}
    | map{ state -> [state.id, state] }
    | integrate_leiden 
    | view {"After AaaS: $it"}
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      // // check id
      // def id = output[0]
      // assert id == "merged" : "Output ID should be `merged`"

      // // check output
      // def state = output[1]
      // assert state instanceof Map : "State should be a map. Found: ${state}"
      // assert state.containsKey("output") : "Output should contain key 'output'."
      // assert state.output.isFile() : "'output' should be a file."
      // assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"
    
    "Output: $output"
  }
}

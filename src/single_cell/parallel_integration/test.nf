nextflow.enable.dsl=2

include { parallel_integration } from params.rootDir + "/target/nextflow/single_cell/parallel_integration/main.nf"
include { assert_h5mu_slots } from params.rootDir + "/target/_test/nextflow/test_workflows/assert_h5mu_slots/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_composed/resources_test/"

// Build the set of slots each selected method is expected to write into the
// merged output, using the workflow's default slot names. bbknn does not
// produce its own integrated embedding, only a UMAP.
def expectedSlots(methods, resolutions) {
  def obs = [], obsm = [], obsp = [], uns = []
  methods.each { method ->
    def prefix = "${method}_integration"
    resolutions.each { r -> obs << "${prefix}_leiden_${r}" }
    obsm << "X_${method}_umap"
    if (method != "bbknn") obsm << "X_${method}_integrated"
    obsp << "${prefix}_neighbor_distances"
    obsp << "${prefix}_neighbor_connectivities"
    uns << "${prefix}_neighbors"
  }
  [obs: obs, obsm: obsm, obsp: obsp, uns: uns]
}

workflow test_wf {
  resources_test = file(params.resources_test)

  // Methods selected per test case, used to derive the expected output slots.
  def methodsById = [
    "all_methods_test": ["harmony", "scvi", "scanorama", "bbknn"],
    "single_method_test": ["harmony"]
  ]
  // Default --leiden_resolution is [1], formatted as Python's str(float).
  def resolutions = ["1.0"]

  output_ch = Channel.fromList(
    [
      [
        id: "all_methods_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        integration_methods: "harmony;scvi;scanorama;bbknn",
        obs_batch: "sample_id",
        obs_covariates: "sample_id",
        scvi_max_epochs: "5"
      ],
      [
        id: "single_method_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        integration_methods: "harmony",
        obs_covariates: "sample_id"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | parallel_integration
    | view { "After parallel_integration: $it" }
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
    // Assert that every expected per-method slot is present in the output h5mu.
    | assert_h5mu_slots.run(
        fromState: { id, state ->
          def slots = expectedSlots(methodsById[id], resolutions)
          [
            "input": state.output,
            "modality": "rna",
            "obs": slots.obs,
            "obsm": slots.obsm,
            "obsp": slots.obsp,
            "uns": slots.uns
          ]
        }
      )

  // Verify both test cases actually ran through the assert step. Without this
  // the per-event assertions above would be silently skipped if no events were
  // emitted, letting a broken run pass.
  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 2 :
          "output channel should contain 2 events, found ${output_list.size()}"
        assert output_list.collect { it[0] } == ["all_methods_test", "single_method_test"] :
          "expected both test cases to complete; found ${output_list.collect { it[0] }}"
      }
}

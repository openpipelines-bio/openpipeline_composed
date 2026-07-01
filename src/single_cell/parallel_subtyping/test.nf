nextflow.enable.dsl=2

include { parallel_subtyping } from params.rootDir + "/target/nextflow/single_cell/parallel_subtyping/main.nf"
include { assert_h5mu_slots } from params.rootDir + "/target/_test/nextflow/test_workflows/assert_h5mu_slots/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_incubator/resources_test/"

workflow test_wf {
  // Subtype the rna modality of a multimodal (rna + prot) sample by splitting
  // on the leiden clusters (used here as the major cell type), annotating each
  // cluster with the pretrained CellTypist model, then merging everything back.
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList(
    [
      [
        id: "subtyping_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        modality: "rna",
        obs_major_cell_type: "harmony_integration_leiden_1.0",
        celltypist_model: resources_test.resolve("annotation_test_data/celltypist_model_Immune_All_Low.pkl"),
        input_var_gene_names: "gene_symbol",
        // gene symbols are not ensembl IDs, so do not strip version suffixes.
        sanitize_ensembl_ids: false,
        annotation_methods: "celltypist"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    | parallel_subtyping
    | view { "After parallel_subtyping: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "subtyping_test" : "Output ID should be the original sample id. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      "Output: $output"
    }
    // The subtyped rna modality should carry the celltypist prediction columns.
    | assert_h5mu_slots.run(
        key: "assert_rna_slots",
        fromState: { id, state ->
          ["input": state.output, "modality": "rna", "obs": ["celltypist_pred", "celltypist_probability"]]
        },
        // assert_h5mu_slots emits no output; keep the state for the next assert.
        toState: { id, output, state -> state }
      )
    // The untouched prot modality should still be present after the merge.
    | assert_h5mu_slots.run(
        key: "assert_prot_modality",
        fromState: { id, state ->
          ["input": state.output, "modality": "prot"]
        }
      )

  // Verify the test case actually ran through the assert steps.
  output_ch
    | toSortedList { a, b -> a[0] <=> b[0] }
    | map { output_list ->
        assert output_list.size() == 1 :
          "output channel should contain 1 event, found ${output_list.size()}"
        assert output_list.collect { ev -> ev[0] } == ["subtyping_test"] :
          "expected the test case to complete; found ${output_list.collect { ev -> ev[0] }}"
      }
}

nextflow.enable.dsl=2

include { parallel_subtyping } from params.rootDir + "/target/nextflow/single_cell/parallel_subtyping/main.nf"
// add_id is an openpipeline dependency; it builds into the version-pinned
// dependency cache rather than target/nextflow (tag set in _viash.yaml).
include { add_id } from params.rootDir + "/target/dependencies/vsh/vsh/openpipeline/v4.2.0/nextflow/metadata/add_id/main.nf"
include { assert_h5mu_slots } from params.rootDir + "/target/_test/nextflow/test_workflows/assert_h5mu_slots/main.nf"
params.resources_test = "s3://openpipelines-bio/openpipeline_composed/resources_test/"

workflow test_wf {
  // Subtype the rna modality of a multimodal (rna + prot) sample. The query
  // carries no cell-type annotation, so add_id first stamps every cell with a
  // "immune" major cell type matching the reference's `compartment` column.
  // parallel_subtyping then splits both query and reference on that column and
  // annotates the single "immune" group with a CellTypist model trained on the
  // matching reference subset, before merging everything back.
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList(
    [
      [
        id: "subtyping_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        modality: "rna",
        obs_major_cell_type: "compartment",
        reference: resources_test.resolve("annotation_test_data/TS_Blood_filtered.h5mu"),
        reference_var_gene_names: "ensemblid",
        reference_obs_target: "cell_type",
        reference_obs_major_cell_type: "compartment",
        reference_var_input: "highly_variable",
        annotation_methods: "celltypist"
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    // Stamp the query cells with a major cell type matching the reference.
    | add_id.run(
        fromState: ["input": "input"],
        args: ["input_id": "immune", "obs_output": "compartment", "make_observation_keys_unique": false],
        toState: ["input": "output"]
      )
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
    // The subtyped rna modality should carry the celltypist prediction columns,
    // suffixed with the reference target they were transferred from.
    | assert_h5mu_slots.run(
        key: "assert_rna_slots",
        fromState: { id, state ->
          ["input": state.output, "modality": "rna", "obs": ["celltypist_pred_cell_type", "celltypist_probability_cell_type"]]
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

workflow test_wf_2 {
  // Exercise --allow_missing_reference_cell_type
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList(
    [
      [
        id: "allow_missing_test",
        input: resources_test.resolve("pbmc_1k_protein_v3/pbmc_1k_protein_v3_mms.h5mu"),
        modality: "rna",
        obs_major_cell_type: "compartment",
        reference: resources_test.resolve("annotation_test_data/TS_Blood_filtered.h5mu"),
        reference_var_gene_names: "ensemblid",
        reference_obs_target: "cell_type",
        reference_obs_major_cell_type: "compartment",
        reference_var_input: "highly_variable",
        annotation_methods: "celltypist",
        allow_missing_reference_cell_type: true
      ]
    ])
    | view { "State at start: $it" }
    | map { state -> [state.id, state] }
    // Stamp the query cells with a major cell type absent from the reference.
    | add_id.run(
        fromState: ["input": "input"],
        args: ["input_id": "missing_cell_type", "obs_output": "compartment", "make_observation_keys_unique": false],
        toState: ["input": "output"]
      )
    | parallel_subtyping
    | view { "After parallel_subtyping: $it" }
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "allow_missing_test" : "Output ID should be the original sample id. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"
      assert state.containsKey("output") : "Output should contain key 'output'."
      assert state.output.isFile() : "'output' should be a file."
      assert state.output.toString().endsWith(".h5mu") : "Output file should end with '.h5mu'. Found: ${state.output}"

      "Output: $output"
    }
    // The passed-through cells are merged back unannotated: the rna modality
    // retains the major cell-type column but must carry no celltypist
    // predictions (the annotation step is skipped for missing cell types).
    | assert_h5mu_slots.run(
        key: "assert_passthrough_rna_slots",
        fromState: { id, state ->
          [
            "input": state.output,
            "modality": "rna",
            "obs": ["compartment"],
            "obs_absent": ["celltypist_pred_cell_type", "celltypist_probability_cell_type"]
          ]
        },
        toState: { id, output, state -> state }
      )
    // The untouched prot modality should still be present after the merge.
    | assert_h5mu_slots.run(
        key: "assert_passthrough_prot_modality",
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
        assert output_list.collect { ev -> ev[0] } == ["allow_missing_test"] :
          "expected the test case to complete; found ${output_list.collect { ev -> ev[0] }}"
      }
}

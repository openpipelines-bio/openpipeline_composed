nextflow.enable.dsl=2

include { cellranger_multi_qc } from params.rootDir + "/target/nextflow/single_cell/cellranger_multi_qc/main.nf"

params.resources_test = "s3://openpipelines-data"

workflow test_wf {
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList([
      [
        id: "sample_anticmv",
        input: [
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R1_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R2_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R1_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R2_001.fastq.gz")
        ],
        gex_reference: resources_test.resolve("reference_gencodev41_chr1/reference_cellranger.tar.gz"),
        feature_reference: resources_test.resolve("10x_5k_anticmv/raw/feature_reference.csv"),
        library_id: ["5k_human_antiCMV_T_TBNK_connect_GEX_1_subset", "5k_human_antiCMV_T_TBNK_connect_AB_subset"],
        library_type: ["Gene Expression", "Antibody Capture"],
        output_raw: "sample_anticmv_raw/",
        output_h5mu: "sample_anticmv.h5mu",
        create_sample_qc_report: true,
        output_qc_report: "sample_anticmv_qc_report_*.html",
        output_processed_h5mu: "sample_anticmv_processed"
      ]
    ])
    | map { state -> [state.id, state] }
    | cellranger_multi_qc
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "combined" : "Output ID should be 'combined'. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"

      assert state.containsKey("output_raw") : "State should contain key 'output_raw'."
      assert state.output_raw.isDirectory() : "'output_raw' should be a directory."

      assert state.containsKey("output_h5mu") : "State should contain key 'output_h5mu'."
      assert state.output_h5mu.isFile() : "'output_h5mu' should be a file."
      assert state.output_h5mu.toString().endsWith(".h5mu") : "output_h5mu should end with '.h5mu'. Found: ${state.output_h5mu}"

      assert state.containsKey("output_qc_report") : "State should contain key 'output_qc_report'."
      assert state.output_qc_report instanceof List : "'output_qc_report' should be a list."
      assert state.output_qc_report.every { it.isFile() } : "All QC report files should exist."

      assert state.containsKey("output_processed_h5mu") : "State should contain key 'output_processed_h5mu'."
      assert state.output_processed_h5mu.isDirectory() : "'output_processed_h5mu' should be a directory."

      "Output: $output"
    }
}

workflow test_wf_ab_only {
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList([
      [
        id: "sample_ab_only",
        input: [
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R1_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R2_001.fastq.gz")
        ],
        gex_reference: resources_test.resolve("reference_gencodev41_chr1/reference_cellranger.tar.gz"),
        feature_reference: resources_test.resolve("10x_5k_anticmv/raw/feature_reference.csv"),
        library_id: ["5k_human_antiCMV_T_TBNK_connect_AB_subset"],
        library_type: ["Antibody Capture"],
        output_raw: "sample_ab_only_raw/",
        output_h5mu: "sample_ab_only.h5mu",
        create_sample_qc_report: true,
        create_multiqc_report: true,
        output_qc_report: "sample_ab_only_qc_report_*.html",
        output_processed_h5mu: "sample_ab_only_processed"
      ]
    ])
    | map { state -> [state.id, state] }
    | cellranger_multi_qc
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "sample_ab_only" : "Output ID should be 'sample_ab_only'. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"

      assert state.containsKey("output_raw") : "State should contain key 'output_raw'."
      assert state.output_raw.isDirectory() : "'output_raw' should be a directory."

      assert state.containsKey("output_h5mu") : "State should contain key 'output_h5mu'."
      assert state.output_h5mu.isFile() : "'output_h5mu' should be a file."

      assert !state.containsKey("output_qc_report") : "State should NOT contain 'output_qc_report' for AB-only input."
      assert !state.containsKey("output_multiqc_report") : "State should NOT contain 'output_multiqc_report' for AB-only input."

      "Output: $output"
    }
}

workflow test_wf_both_reports {
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList([
      [
        id: "sample_both_reports",
        input: [
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R1_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R2_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R1_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R2_001.fastq.gz")
        ],
        gex_reference: resources_test.resolve("reference_gencodev41_chr1/reference_cellranger.tar.gz"),
        feature_reference: resources_test.resolve("10x_5k_anticmv/raw/feature_reference.csv"),
        library_id: ["5k_human_antiCMV_T_TBNK_connect_GEX_1_subset", "5k_human_antiCMV_T_TBNK_connect_AB_subset"],
        library_type: ["Gene Expression", "Antibody Capture"],
        output_raw: "sample_both_reports_raw/",
        output_h5mu: "sample_both_reports.h5mu",
        create_sample_qc_report: true,
        create_multiqc_report: true,
        output_qc_report: "sample_both_reports_qc_report_*.html",
        output_processed_h5mu: "sample_both_reports_processed"
      ]
    ])
    | map { state -> [state.id, state] }
    | cellranger_multi_qc
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "combined" : "Output ID should be 'combined'. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"

      assert state.containsKey("output_raw") : "State should contain key 'output_raw'."
      assert state.output_raw.isDirectory() : "'output_raw' should be a directory."

      assert state.containsKey("output_h5mu") : "State should contain key 'output_h5mu'."
      assert state.output_h5mu.isFile() : "'output_h5mu' should be a file."
      assert state.output_h5mu.toString().endsWith(".h5mu") : "output_h5mu should end with '.h5mu'."

      assert state.containsKey("output_multiqc_report") : "State should contain key 'output_multiqc_report'."
      assert state.output_multiqc_report.isDirectory() : "'output_multiqc_report' should be a directory."

      assert state.containsKey("output_qc_report") : "State should contain key 'output_qc_report'."
      assert state.output_qc_report instanceof List : "'output_qc_report' should be a list."
      assert state.output_qc_report.every { it.isFile() } : "All QC report files should exist."

      assert state.containsKey("output_processed_h5mu") : "State should contain key 'output_processed_h5mu'."
      assert state.output_processed_h5mu.isDirectory() : "'output_processed_h5mu' should be a directory."

      "Output: $output"
    }
}

workflow test_wf_multiqc_only {
  resources_test = file(params.resources_test)

  output_ch = Channel.fromList([
      [
        id: "sample_multiqc_only",
        input: [
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R1_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_GEX_1_subset_S1_L001_R2_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R1_001.fastq.gz"),
          resources_test.resolve("10x_5k_anticmv/raw/5k_human_antiCMV_T_TBNK_connect_AB_subset_S2_L004_R2_001.fastq.gz")
        ],
        gex_reference: resources_test.resolve("reference_gencodev41_chr1/reference_cellranger.tar.gz"),
        feature_reference: resources_test.resolve("10x_5k_anticmv/raw/feature_reference.csv"),
        library_id: ["5k_human_antiCMV_T_TBNK_connect_GEX_1_subset", "5k_human_antiCMV_T_TBNK_connect_AB_subset"],
        library_type: ["Gene Expression", "Antibody Capture"],
        output_raw: "sample_multiqc_only_raw/",
        output_h5mu: "sample_multiqc_only.h5mu",
        create_multiqc_report: true
      ]
    ])
    | map { state -> [state.id, state] }
    | cellranger_multi_qc
    | view { output ->
      assert output.size() == 2 : "Outputs should contain two elements; [id, state]"

      def id = output[0]
      assert id == "sample_multiqc_only" : "Output ID should be 'sample_multiqc_only'. Found: ${id}"

      def state = output[1]
      assert state instanceof Map : "State should be a map. Found: ${state}"

      assert state.containsKey("output_raw") : "State should contain key 'output_raw'."
      assert state.output_raw.isDirectory() : "'output_raw' should be a directory."

      assert state.containsKey("output_h5mu") : "State should contain key 'output_h5mu'."
      assert state.output_h5mu.isFile() : "'output_h5mu' should be a file."
      assert state.output_h5mu.toString().endsWith(".h5mu") : "output_h5mu should end with '.h5mu'."

      assert state.containsKey("output_multiqc_report") : "State should contain key 'output_multiqc_report'."
      assert state.output_multiqc_report.isDirectory() : "'output_multiqc_report' should be a directory."

      assert !state.containsKey("output_qc_report") : "State should NOT contain 'output_qc_report' when only MultiQC is enabled."
      assert !state.containsKey("output_processed_h5mu") : "State should NOT contain 'output_processed_h5mu' when only MultiQC is enabled."

      "Output: $output"
    }
}

workflow run_wf {
  take:
    input_ch

  main:
    output_ch = input_ch
      | map { id, state ->
          [id, state + [_meta: [join_id: id]]]
        }

      // Step 1 (optional): FastQC on the input FASTQ files
      | fastqc.run(
          runIf: { id, state -> state.create_multiqc_report },
          fromState: { id, state ->
            def fastq_files = state.gex_input ?: state.input
            def fastq_dir = fastq_files instanceof List ? fastq_files[0].parent : fastq_files?.parent
            [
              input: fastq_dir,
              output: "${id}_fastqc"
            ]
          },
          args: [mode: "dir"],
          toState: { id, output, state ->
            state + [output_fastqc: output.output]
          }
        )

      // Step 2: Cell Ranger multi
      | cellranger_multi.run(
          fromState: { id, state -> state },
          toState: { id, output, state ->
            state + [
              output_raw: output.output_raw,
              output_h5mu: output.output_h5mu
            ]
          }
        )

      // Step 3 (optional): MultiQC using FastQC results and CellRanger raw output
      | multiqc.run(
          runIf: { id, state -> state.create_multiqc_report },
          fromState: { id, state ->
            [
              input: [state.output_fastqc, state.output_raw],
              output: state.output_multiqc_report ?: "${id}_multiqc"
            ]
          },
          toState: { id, output, state ->
            state + [output_multiqc_report: output.output]
          }
        )

      // Step 4 (optional): Sample QC report
      | generate_qc_report.run(
          runIf: { id, state -> state.create_sample_qc_report },
          fromState: { id, state ->
            [
              id: id,
              input: state.output_h5mu,
              ingestion_method: "cellranger_multi",
              run_cellbender: state.run_cellbender ?: false,
              output_qc_report: state.output_qc_report ?: "${id}_qc_report_*.html",
              output_processed_h5mu: state.output_processed_h5mu ?: "processed_h5mu"
            ]
          },
          toState: { id, output, state ->
            state + [
              output_qc_report: output.output_qc_report,
              output_processed_h5mu: output.output_processed_h5mu
            ]
          }
        )

      | map { id, state ->
          def out = [
            output_raw: state.output_raw,
            output_h5mu: state.output_h5mu
          ]
          if (state._meta) out._meta = state._meta
          // output_qc_report is multiple:true → List[Path] when produced
          if (state.output_qc_report instanceof List && state.output_qc_report.any { it instanceof java.nio.file.Path }) {
            out.output_qc_report = state.output_qc_report
          }
          if (state.output_processed_h5mu instanceof java.nio.file.Path) out.output_processed_h5mu = state.output_processed_h5mu
          if (state.output_multiqc_report instanceof java.nio.file.Path) out.output_multiqc_report = state.output_multiqc_report
          [id, out]
        }

  emit:
    output_ch
}

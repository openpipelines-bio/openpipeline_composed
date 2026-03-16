workflow run_wf {
  take:
    input_ch

  main:
    output_ch = input_ch
      | map { id, state ->
          [id, state + [_meta: [join_id: id]]]
        }

      | fastqc.run(
          runIf: { id, state -> state.create_multiqc_report },
          fromState: { id, state ->
            def fastq_files = state.gex_input ?: state.input
            [
              input: fastq_files[0].parent,
              output: "${id}_fastqc"
            ]
          },
          args: [mode: "dir"],
          toState: { id, output, state ->
            state + [output_fastqc: output.output]
          }
        )

      | cellranger_multi.run(
          fromState: { id, state -> state },
          toState: { id, output, state ->
            state + [
              output_raw: output.output_raw,
              output_h5mu: output.output_h5mu
            ]
          }
        )

      | multiqc.run(
          runIf: { id, state -> state.create_multiqc_report },
          fromState: { id, state ->
            [
              input: [state.output_fastqc, state.output_raw],
              output: state.output_multiqc_report
            ]
          },
          toState: { id, output, state ->
            state + [_multiqc_produced: true, output_multiqc_report: output.output]
          }
        )

      | generate_qc_report.run(
          runIf: { id, state -> state.create_sample_qc_report },
          fromState: { id, state ->
            [
              id: id,
              input: state.output_h5mu,
              ingestion_method: "cellranger_multi",
              run_cellbender: state.run_cellbender,
              output_qc_report: state.output_qc_report,
              output_processed_h5mu: state.output_processed_h5mu
            ]
          },
          toState: { id, output, state ->
            state + [
              _qc_report_produced: true,
              output_qc_report: output.output_qc_report,
              output_processed_h5mu: output.output_processed_h5mu
            ]
          }
        )

      | map { id, state ->
          def out = [output_raw: state.output_raw, output_h5mu: state.output_h5mu]
          if (state._meta) out._meta = state._meta
          if (state._multiqc_produced) out.output_multiqc_report = state.output_multiqc_report
          if (state._qc_report_produced) {
            out.output_qc_report = state.output_qc_report
            out.output_processed_h5mu = state.output_processed_h5mu
          }
          [id, out]
        }

  emit:
    output_ch
}

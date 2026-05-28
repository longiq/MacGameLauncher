import SwiftUI

struct InstallerProgressView: View {
    let job: InstallerJob
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installing \(job.name)")
                        .font(.headline)
                    Text("into "\(job.bottle.name)"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Progress section
            Group {
                switch job.phase {
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Downloading…")
                            Spacer()
                            if progress > 0 {
                                Text("\(Int(progress * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        if progress > 0 {
                            ProgressView(value: progress).progressViewStyle(.linear)
                        } else {
                            ProgressView().progressViewStyle(.linear)
                        }
                    }

                case .running:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Running Windows installer via Wine…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                case .complete:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        Text("Installation complete!")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                case .failed(let message):
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("Installation failed")
                                .fontWeight(.medium)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Log output
            VStack(alignment: .leading, spacing: 4) {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(job.logOutput.isEmpty ? "(no output)" : job.logOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .id("logEnd")
                    }
                    .frame(height: 160)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: job.logOutput) { _, _ in
                        proxy.scrollTo("logEnd", anchor: .bottom)
                    }
                }
            }

            // Action buttons
            HStack {
                Spacer()
                if job.phase.isTerminal {
                    Button("Close") {
                        store.removeInstallerJob(job)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel", role: .cancel) {
                        job.cancel()
                        store.removeInstallerJob(job)
                        dismiss()
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 460, maxWidth: 560)
    }
}

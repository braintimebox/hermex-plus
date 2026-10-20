import SwiftUI

/// Alpha surface for OpenRouter's Decisions API. Deliberately outside the model
/// picker: a decisions model cannot answer a chat turn, so offering it as a
/// session model would be a lie.
struct DecisionsView: View {
    @State private var viewModel = DecisionsViewModel()

    var body: some View {
        Form {
            Section {
                SecureField("OpenRouter API key", text: $viewModel.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { viewModel.saveKey() }
            } header: {
                Text("Access")
            } footer: {
                Text("Stored in Keychain on this device. A decisions model is not a chat model — it answers questions about a piece of text, it does not talk.")
            }

            Section("Input") {
                Picker("Model", selection: $viewModel.model) {
                    if viewModel.models.isEmpty {
                        Text(viewModel.model).tag(viewModel.model)
                    } else {
                        ForEach(viewModel.models) { info in
                            Text(info.displayName).tag(info.id)
                        }
                    }
                }
                .task { viewModel.loadSavedKey(); await viewModel.loadModels() }

                Button {
                    Task { await viewModel.reloadModels() }
                } label: {
                    Label("Reload model list", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isRunning)
                .accessibilityHint("Fetches the decision models again with the current key.")

                TextField("State — the text to decide about", text: $viewModel.state, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("Questions") {
                ForEach($viewModel.questions) { $question in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Type", selection: $question.kind) {
                            ForEach(DecisionQuestion.Kind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        TextField("Instruction", text: $question.instructions, axis: .vertical)
                            .lineLimit(1...3)

                        switch question.kind {
                        case .choice:
                            TextField("Options, comma separated", text: $question.choices)
                        case .score:
                            TextField("Levels, low to high", text: $question.levels)
                        case .noul:
                            EmptyView()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    viewModel.questions.remove(atOffsets: offsets)
                }

                Button {
                    viewModel.questions.append(DecisionsViewModel.EditableQuestion())
                } label: {
                    Label("Add question", systemImage: "plus.circle")
                }
            }

            Section {
                Button {
                    Task { await viewModel.run() }
                } label: {
                    HStack {
                        if viewModel.isRunning { ProgressView().controlSize(.small) }
                        Text(viewModel.isRunning ? "Running…" : "Run decision")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canRun)
            }

            if let result = viewModel.result {
                Section("Answers") {
                    ForEach(result.answers.keys.sorted(), id: \.self) { key in
                        if let answer = result.answers[key] {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(viewModel.questionTitles[key] ?? key)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(answer.summary)
                                    .font(.body.monospacedDigit())
                            }
                            .padding(.vertical, 3)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let usage = result.usage {
                    Section {
                        LabeledContent("Tokens", value: "\(usage.inputTokens ?? 0) in / \(usage.outputTokens ?? 0) out")
                        if let cost = usage.cost {
                            LabeledContent("Cost", value: String(format: "$%.6f", cost))
                        }
                        if let provider = result.provider {
                            LabeledContent("Provider", value: provider)
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Decisions (alpha)")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { viewModel.saveKey() }
    }
}

#Preview {
    NavigationStack { DecisionsView() }
}

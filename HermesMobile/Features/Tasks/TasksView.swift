import SwiftUI
import SwiftData

struct TasksView: View {
    let server: URL
    let onAPIError: (Error) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TasksViewModel
    @State private var isPresentingCreateTask = false
    /// Count of pending scheduled messages. Loaded asynchronously off the main
    /// thread — a `@Query` here performed a synchronous SwiftData fetch at view
    /// construction and froze opening Tasks over a busy store (same freeze class
    /// as ScheduledMessagesView on v1.4.5).
    @State private var scheduledCount = 0

    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: TasksViewModel(server: server))
    }

    var body: some View {
        content
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.clearActionError()
                        isPresentingCreateTask = true
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .disabled(viewModel.isMutating)

                    Button {
                        Task { await loadTasks() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .sheet(isPresented: $isPresentingCreateTask) {
                CronJobEditorSheet(
                    title: String(localized: "New Task"),
                    draft: CronJobEditorDraft(),
                    saveTitle: String(localized: "Create"),
                    isSaving: viewModel.isMutating,
                    errorMessage: viewModel.actionErrorMessage,
                    deliveryOptions: viewModel.deliveryOptions
                ) { draft in
                    let didCreate = await viewModel.create(from: draft)
                    if let lastError = viewModel.lastError {
                        onAPIError(lastError)
                    }
                    return didCreate
                }
            }
            .task {
                MainThreadWatchdog.shared.setScreen("TasksView")
                HermexLogger.shared.log(type: "event", screen: "TasksView", message: "tasks opened")
                await loadTasks()
                await loadScheduledCount()
            }
            .onAppear {
                // Refresh the count when returning from the Scheduled list
                // (rows may have been sent/deleted there).
                Task { await loadScheduledCount() }
            }
    }

    /// Count pending scheduled messages on a detached context so a busy store
    /// never blocks the main thread (the old `@Query` did exactly that).
    private func loadScheduledCount() async {
        let container = modelContext.container
        let count = await Task.detached(priority: .userInitiated) { () -> Int in
            let ctx = ModelContext(container)
            let descriptor = FetchDescriptor<PendingScheduledMessage>()
            return (try? ctx.fetchCount(descriptor)) ?? 0
        }.value
        scheduledCount = count
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.jobs.isEmpty {
            ProgressView("Loading tasks...")
        } else if let errorMessage = viewModel.errorMessage, viewModel.jobs.isEmpty {
            ContentUnavailableView {
                Label("Could Not Load Tasks", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    Task { await loadTasks() }
                }
            }
        } else if viewModel.jobs.isEmpty {
            ContentUnavailableView {
                Label("No Tasks", systemImage: "calendar.badge.clock")
            } description: {
                Text("Scheduled jobs from the Hermes server will appear here.")
            }
        } else {
            List {
                if scheduledCount > 0 {
                    Section {
                        NavigationLink {
                            ScheduledMessagesView { msg in
                                await sendScheduledNow(msg)
                            }
                        } label: {
                            HStack {
                                Label("Scheduled Messages", systemImage: "calendar.badge.clock")
                                Spacer()
                                Text("\(scheduledCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Label("Running now", systemImage: "bolt.fill")
                        Spacer()
                        Text("\(viewModel.activeRunningCount)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Scheduled Jobs") {
                    ForEach(viewModel.jobs) { job in
                        NavigationLink {
                            TaskDetailView(
                                job: job,
                                runningElapsed: viewModel.runningElapsed(for: job),
                                server: server,
                                onAPIError: onAPIError,
                                onMutation: { mutation in
                                    viewModel.apply(mutation)
                                }
                            )
                        } label: {
                            CronJobRowView(
                                job: job,
                                runningElapsed: viewModel.runningElapsed(for: job)
                            )
                        }
                    }
                }
            }
            .refreshable {
                await loadTasks()
            }
        }
    }

    private func loadTasks() async {
        await viewModel.load()

        if let lastError = viewModel.lastError {
            onAPIError(lastError)
        }
    }

    /// Send a scheduled message immediately (the "Send Now" button).
    /// Mirrors `dispatchDueScheduledMessages` in SessionListViewModel: creates
    /// a session when the message has no sessionId, sends via startChat, then
    /// removes the pending row.
    private func sendScheduledNow(_ msg: PendingScheduledMessage) async {
        guard !msg.draftText.isEmpty,
              let serverURL = URL(string: msg.serverURLString) else { return }

        HermexLogger.shared.log(
            type: "event",
            screen: "TasksView",
            message: "send now tapped session=\(msg.sessionId)"
        )

        let apiClient = APIClient(baseURL: serverURL)
        var targetSessionId = msg.sessionId
        if targetSessionId.isEmpty {
            do {
                let response = try await apiClient.createSession(
                    workspace: nil, model: nil, modelProvider: nil, profile: nil
                )
                targetSessionId = response.session?.sessionId ?? ""
                if !targetSessionId.isEmpty,
                   let title = msg.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    _ = try? await apiClient.renameSession(id: targetSessionId, title: title)
                }
            } catch {
                onAPIError(error)
                return
            }
        }
        guard !targetSessionId.isEmpty else { return }

        do {
            _ = try await apiClient.startChat(
                sessionID: targetSessionId,
                message: msg.draftText,
                workspace: nil,
                model: nil
            )
            // Capture scalars BEFORE deleting the row — the model must not be
            // touched after delete.
            let scheduleKey = msg.scheduleKey
            let serverURLString = msg.serverURLString
            modelContext.delete(msg)
            try? modelContext.save()
            // Cancel the server timer so the message is NOT re-sent
            // automatically at its scheduled time (duplicate-delivery bug).
            await PendingScheduledMessage.deleteFromServer(
                scheduleKey: scheduleKey,
                serverURLString: serverURLString
            )
        } catch {
            onAPIError(error)
        }
    }
}

private struct CronJobRowView: View {
    let job: CronJob
    let runningElapsed: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(job.displayName)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 8)

                StatusBadge(
                    text: runningElapsed == nil ? job.status.label : String(localized: "Running"),
                    color: statusColor
                )
            }

            if let prompt = job.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 6) {
                CronJobMetadataRow(
                    title: String(localized: "Schedule"),
                    value: job.scheduleText ?? String(localized: "Not available")
                )

                CronJobMetadataRow(
                    title: String(localized: "Next"),
                    value: job.nextRunAt?.formatted ?? String(localized: "Not available")
                )

                CronJobMetadataRow(
                    title: String(localized: "Last"),
                    value: job.lastRunAt?.formatted ?? String(localized: "Never")
                )

                if let runningElapsed {
                    CronJobMetadataRow(
                        title: String(localized: "Elapsed"),
                        value: Self.elapsedText(runningElapsed)
                    )
                }

                CronJobMetadataRow(
                    title: String(localized: "Deliver"),
                    value: job.deliver ?? "local"
                )

                if let model = job.model, !model.isEmpty {
                    CronJobMetadataRow(title: String(localized: "Model"), value: model)
                }

                if let provider = job.provider, !provider.isEmpty {
                    CronJobMetadataRow(title: String(localized: "Provider"), value: provider)
                }

                if let profile = job.profile, !profile.isEmpty {
                    CronJobMetadataRow(title: String(localized: "Profile"), value: profile)
                }

                if let skills = job.skills, !skills.isEmpty {
                    CronJobMetadataRow(title: String(localized: "Skills"), value: skills.joined(separator: ", "))
                }

                if let error = job.lastError ?? job.lastDeliveryError, !error.isEmpty {
                    CronJobMetadataRow(title: String(localized: "Error"), value: error)
                        .foregroundStyle(.red)
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        if runningElapsed != nil {
            return .blue
        }

        switch job.status {
        case .active:
            return .green
        case .paused, .off:
            return .orange
        case .error:
            return .red
        case .needsAttention:
            return .yellow
        }
    }

    private static func elapsedText(_ elapsed: Double) -> String {
        if elapsed < 60 {
            return "\(Int(elapsed.rounded()))s"
        }

        let minutes = Int(elapsed / 60)
        let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }
}

struct CronJobEditorSheet: View {
    let title: String
    let saveTitle: String
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (CronJobEditorDraft) async -> Bool

    @State private var draft: CronJobEditorDraft
    @Environment(\.dismiss) private var dismiss

    /// Server-provided deliver targets. A plain `let` so a re-init while the
    /// sheet is presented (options finishing their async load) swaps in the
    /// fresh list, unlike `@State draft`, which keeps the user's edits.
    private let serverDeliveryOptions: [CronDeliveryOption]?
    /// The draft's deliver value when the editor opened; stable across
    /// re-inits because callers rebuild the same draft.
    private let initialDeliver: String

    /// Picker rows recomputed from the live draft so a value typed while the
    /// options were still loading keeps a matching row, and the initial
    /// unknown/legacy value keeps its custom row even after the user selects
    /// another option. `nil` means fall back to free-text entry.
    private var deliverPickerOptions: [CronDeliverPickerOption]? {
        CronDeliverPicker.options(
            serverOptions: serverDeliveryOptions,
            currentValue: draft.deliver,
            initialValue: initialDeliver
        )
    }

    init(
        title: String,
        draft: CronJobEditorDraft,
        saveTitle: String,
        isSaving: Bool,
        errorMessage: String?,
        deliveryOptions: [CronDeliveryOption]? = nil,
        onSave: @escaping (CronJobEditorDraft) async -> Bool
    ) {
        self.title = title
        self.saveTitle = saveTitle
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.serverDeliveryOptions = deliveryOptions
        self.initialDeliver = draft.deliver
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Name", text: $draft.name)

                    TextField("Prompt", text: $draft.prompt, axis: .vertical)
                        .lineLimit(3...8)

                    TextField("Schedule", text: $draft.schedule)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Delivery") {
                    if let deliverPickerOptions {
                        Picker("Deliver", selection: $draft.deliver) {
                            ForEach(deliverPickerOptions) { option in
                                Group {
                                    if option.isCustom {
                                        Text("\(option.label) (custom)")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                                .tag(option.value)
                            }
                        }
                    } else {
                        TextField("Deliver", text: $draft.deliver)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Toggle("Toast Notifications", isOn: $draft.toastNotifications)
                }

                Section("Configuration") {
                    TextField("Skills", text: $draft.skillsText, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Model", text: $draft.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Provider", text: $draft.provider)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Profile", text: $draft.profile)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let formMessage {
                    Section {
                        Text(formMessage)
                            .font(.footnote)
                            .foregroundStyle(messageColor)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await onSave(draft) {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(saveTitle)
                        }
                    }
                    .disabled(isSaving || draft.validationMessage != nil)
                }
            }
        }
        .adaptiveFormPresentation()
    }

    private var formMessage: String? {
        errorMessage ?? draft.validationMessage
    }

    private var messageColor: Color {
        errorMessage == nil ? .secondary : .red
    }
}

struct CronJobMetadataRow: View {
    let title: String
    let value: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    valueText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleText
                        .frame(width: 64, alignment: .leading)
                    valueText
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        Text(title)
            .foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(value)
            .foregroundStyle(.primary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

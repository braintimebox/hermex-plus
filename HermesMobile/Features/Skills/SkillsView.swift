import SwiftUI

struct SkillsView: View {
    let server: URL
    let onAPIError: (Error) -> Void

    @State private var viewModel: SkillsViewModel
    @State private var selectedSkill: SkillSummary?
    @State private var searchText = ""
    /// Collapsed state per origin section title ("Personal" / "Built-in"). Both
    /// start expanded; tapping the lightweight section header toggles. Persisted
    /// nowhere — it's a per-visit convenience, defaulting to everything visible.
    @State private var collapsedSections: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: SkillsViewModel(server: server))
    }

    var body: some View {
        content
            .adaptiveReadableScrollContent(maxWidth: AdaptiveReadableContentWidth.secondaryDestination)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    originTitleHeader
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadSkills() }
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
            .task {
                await loadSkills()
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search skills...")
    }

    /// Two-line title in the nav bar: "Skills" (parent) with the current
    /// Personal/Built-in level beneath it as a small secondary caption. Keeps
    /// the origin context pinned at the very top, next to "Skills", instead of
    /// as a section header in the middle of the scrolling list.
    private var originTitleHeader: some View {
        VStack(spacing: 1) {
            Text("Skills")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(originSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// "Personal · Built-in" — a compact summary of the two sections, shown as
    /// the subtitle under "Skills".
    private var originSubtitle: String {
        let titles = filteredSections.map(\.title)
        guard !titles.isEmpty else { return "" }
        return titles.joined(separator: " · ")
    }

    private var filteredSections: [(title: String, groups: [(category: String, skills: [SkillSummary])])] {
        viewModel.filteredOriginGroupedSections(searchText: searchText)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.skills.isEmpty {
            ProgressView("Loading skills...")
        } else if let errorMessage = viewModel.errorMessage, viewModel.skills.isEmpty {
            ContentUnavailableView {
                Label("Could Not Load Skills", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    Task { await loadSkills() }
                }
            }
        } else if viewModel.skills.isEmpty {
            ContentUnavailableView {
                Label("No Skills", systemImage: "hammer")
            } description: {
                Text("Skills from the Hermes server will appear here.")
            }
        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredSections.isEmpty {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } description: {
                Text("No skills match \"\(searchText)\".")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(filteredSections, id: \.title) { section in
                        originSection(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                await loadSkills()
            }
            .background(Color(.systemBackground))
        }
    }

    private func loadSkills() async {
        await viewModel.load()
        if let error = viewModel.lastError {
            onAPIError(error)
        }
    }

    private func toggle(skill: SkillSummary, enabled: Bool) async {
        await viewModel.setSkill(skill, enabled: enabled)
        if let error = viewModel.lastError {
            onAPIError(error)
        }
    }

    /// A collapsible origin bucket. The header is a thin, native iOS caption —
    /// small gray UPPERCASE with a trailing chevron, no "Skills ›" breadcrumb,
    /// no sticker plate — mirroring the previous "native section header" idiom
    /// while remaining tappable to collapse/expand the bucket.
    @ViewBuilder
    private func originSection(_ section: (title: String, groups: [(category: String, skills: [SkillSummary])])) -> some View {
        let isCollapsed = collapsedSections.contains(section.title)

        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(ChatMotion.quickState(reduceMotion: accessibilityReduceMotion)) {
                    if isCollapsed {
                        collapsedSections.remove(section.title)
                    } else {
                        collapsedSections.insert(section.title)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(section.title)
                        .textCase(.uppercase)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 16) {
                    sectionGroups(section.groups)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionGroups(_ groups: [(category: String, skills: [SkillSummary])]) -> some View {
        ForEach(groups, id: \.category) { group in
            SkillCategorySection(
                category: group.category,
                skills: group.skills,
                server: server,
                togglingSkillNames: viewModel.togglingSkillNames,
                onToggleSkill: { skill, enabled in
                    await toggle(skill: skill, enabled: enabled)
                },
                onAPIError: onAPIError
            )
        }
    }
}

private struct SkillCategorySection: View {
    let category: String
    let skills: [SkillSummary]
    let server: URL
    let togglingSkillNames: Set<String>
    let onToggleSkill: (SkillSummary, Bool) async -> Void
    let onAPIError: (Error) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category)
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(skills.enumerated()), id: \.offset) { index, skill in
                    NavigationLink {
                        SkillDetailView(
                            skill: skill,
                            server: server,
                            onAPIError: onAPIError
                        )
                    } label: {
                        SkillRow(
                            skill: skill,
                            isToggling: isToggling(skill),
                            onToggle: canToggle(skill) ? { enabled in
                                Task { await onToggleSkill(skill, enabled) }
                            } : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(skill.disabled == true ? 0.55 : 1)
                    .contextMenu {
                        if canToggle(skill) {
                            let isDisabled = skill.disabled == true
                            Button {
                                Task { await onToggleSkill(skill, isDisabled) }
                            } label: {
                                Label(isDisabled ? "Enable" : "Disable", systemImage: isDisabled ? "checkmark.circle" : "pause.circle")
                            }
                            .disabled(isToggling(skill))
                        }
                    }

                    if index < skills.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func canToggle(_ skill: SkillSummary) -> Bool {
        guard skill.disabled != nil else { return false }
        let name = skill.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(name ?? "").isEmpty
    }

    private func isToggling(_ skill: SkillSummary) -> Bool {
        guard let name = skill.name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return togglingSkillNames.contains(name)
    }
}

private struct SkillRow: View {
    let skill: SkillSummary
    var isToggling: Bool = false
    var onToggle: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if skill.disabled == true || !tags.isEmpty {
                    HStack(spacing: 6) {
                        if skill.disabled == true {
                            Text("Disabled")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .foregroundStyle(.secondary)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }

                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .foregroundStyle(.secondary)
                                .background(Color(.secondarySystemFill).opacity(0.8), in: Capsule())
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if let onToggle {
                Toggle(skill.disabled == true ? "Enable" : "Disable", isOn: Binding(
                    get: { skill.disabled != true },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.8, anchor: .trailing)
                .disabled(isToggling)
                .padding(.top, 6)
            }

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let onToggle {
                Button(skill.disabled == true ? "Enable" : "Disable") {
                    guard !isToggling else { return }
                    onToggle(skill.disabled == true)
                }
            }
        }
    }

    private var displayName: String {
        let name = skill.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else {
            return String(localized: "Unnamed Skill")
        }
        return name
    }

    private var description: String? {
        let text = skill.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private var tags: [String] {
        (skill.tags ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct SkillDetailView: View {
    let skill: SkillSummary
    let server: URL
    let onAPIError: (Error) -> Void

    @State private var detail: SkillDetailResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFile: String?
    @State private var fileContent: String?
    @State private var isLoadingFile = false

    var body: some View {
        content
            .navigationTitle(skill.name ?? String(localized: "Skill"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadDetail() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadDetail()
            }
            .sheet(item: $selectedFile) { fileName in
                NavigationStack {
                    SkillLinkedFileView(
                        fileName: fileName,
                        content: fileContent,
                        isLoading: isLoadingFile
                    )
                }
                .adaptivePagePresentation()
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && detail == nil {
            ProgressView("Loading skill...")
        } else if let errorMessage, detail == nil {
            ContentUnavailableView {
                Label("Could Not Load Skill", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    Task { await loadDetail() }
                }
            }
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let content = detail.content, !content.isEmpty {
                        MarkdownRenderer(content: content)
                            .padding(.horizontal)
                    }

                    if let linkedFiles = detail.linkedFiles, !linkedFiles.isEmpty {
                        SkillLinkedFilesSection(
                            fileNames: linkedFiles,
                            onSelect: { fileName in
                                Task { await loadLinkedFile(named: fileName) }
                            }
                        )
                    }
                }
                .padding(.vertical)
            }
        } else {
            ContentUnavailableView {
                Label("No Content", systemImage: "doc.text")
            } description: {
                Text("This skill has no content.")
            }
        }
    }

    private func loadDetail() async {
        guard let name = skill.name else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient(baseURL: server).skillContent(name: name)
            detail = response
        } catch {
            errorMessage = error.localizedDescription
            onAPIError(error)
        }
    }

    private func loadLinkedFile(named fileName: String) async {
        guard let name = skill.name else { return }
        isLoadingFile = true
        selectedFile = fileName
        defer { isLoadingFile = false }

        do {
            let response = try await APIClient(baseURL: server).skillContent(name: name, file: fileName)
            fileContent = response.content
        } catch {
            fileContent = String(localized: "Could not load file: \(error.localizedDescription)")
        }
    }
}

private struct SkillLinkedFilesSection: View {
    let fileNames: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linked Files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(fileNames.enumerated()), id: \.element) { index, fileName in
                    Button {
                        onSelect(fileName)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(width: 34, height: 34)
                                .background(Color(.tertiarySystemFill).opacity(0.7), in: Circle())

                            Text(fileName)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < fileNames.count - 1 {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct SkillLinkedFileView: View {
    let fileName: String
    let content: String?
    let isLoading: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading file...")
            } else if let content, !content.isEmpty {
                ScrollView {
                    MarkdownRenderer(content: content)
                        .padding()
                }
            } else {
                ContentUnavailableView {
                    Label("No Content", systemImage: "doc.text")
                } description: {
                    Text("This file appears to be empty.")
                }
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

/// Two-section screen: Plugins (top) and Hooks (below), fed live from the
/// Hermes server's read-only `GET /api/plugins` endpoint. Plugins render one
/// row each (name, version, kind/activation badge, description). Hooks are the
/// union of lifecycle hooks registered across plugins, grouped by hook name.
@MainActor
struct PluginsHooksView: View {
    let server: URL
    let onAPIError: (Error) -> Void

    @State private var viewModel: PluginsHooksViewModel
    /// Collapsed state for the "Personal" / "Built-in" plugin buckets and the
    /// "Hooks" group. All expanded by default; tap the caption to toggle.
    @State private var collapsedSections: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: PluginsHooksViewModel(server: server))
    }

    var body: some View {
        content
            .adaptiveReadableScrollContent(maxWidth: AdaptiveReadableContentWidth.secondaryDestination)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    pluginsTitleHeader
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
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
            .task {
                await load()
            }
    }

    /// Two-line title in the nav bar: "Plugins / Hooks" with the origin
    /// summary (Personal · Built-in) beneath it — keeps the split pinned at the
    /// top instead of as section headers inside the scrolling list.
    private var pluginsTitleHeader: some View {
        VStack(spacing: 1) {
            Text("Plugins / Hooks")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(originSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var originSubtitle: String {
        let titles = viewModel.originGroupedPlugins.map(\.title)
        guard !titles.isEmpty else { return "" }
        return titles.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.plugins.isEmpty {
            ProgressView("Loading plugins...")
        } else if let error = viewModel.errorMessage, viewModel.plugins.isEmpty {
            ContentUnavailableView {
                Label("Could Not Load Plugins", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if viewModel.plugins.isEmpty {
            ContentUnavailableView {
                Label("No Plugins", systemImage: "puzzlepiece.extension")
            } description: {
                Text("Plugins and hooks from the Hermes server will appear here.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.originGroupedPlugins, id: \.title) { section in
                            pluginOriginSection(section)
                        }
                    }

                    hooksSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                await load()
            }
            .background(Color(.systemBackground))
        }
    }

    /// One plugin origin bucket (Personal / Built-in). Collapsible: a thin
    /// native caption header (gray UPPERCASE + chevron) toggles the rows.
    @ViewBuilder
    private func pluginOriginSection(_ section: (title: String, plugins: [PluginSummary])) -> some View {
        let isCollapsed = collapsedSections.contains(section.title)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(ChatMotion.quickState(reduceMotion: accessibilityReduceMotion)) {
                    if isCollapsed {
                        collapsedSections.remove(section.title)
                    } else {
                        collapsedSections.insert(section.title)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(section.title)
                        .textCase(.uppercase)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                pluginRows(section.plugins)
            }
        }
    }

    @ViewBuilder
    private func pluginRows(_ plugins: [PluginSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plugins.enumerated()), id: \.element.id) { index, plugin in
                PluginRow(plugin: plugin)
                if index < plugins.count - 1 {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var hooksSection: some View {
        let grouped = viewModel.groupedHooks
        if !grouped.isEmpty {
            let isCollapsed = collapsedSections.contains("Hooks")

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(ChatMotion.quickState(reduceMotion: accessibilityReduceMotion)) {
                        if isCollapsed {
                            collapsedSections.remove("Hooks")
                        } else {
                            collapsedSections.insert("Hooks")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Hooks")
                            .textCase(.uppercase)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isCollapsed ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isCollapsed {
                    VStack(spacing: 0) {
                        ForEach(Array(grouped.enumerated()), id: \.element.hook) { index, entry in
                            HookRow(hook: entry.hook, providers: entry.providers)
                            if index < grouped.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
        }
    }

    private func load() async {
        await viewModel.load()
        if let error = viewModel.lastError {
            onAPIError(error)
        }
    }
}

/// Aggregated hook → list of plugin names that register it.
struct HookEntry: Identifiable {
    let hook: String
    let providers: [String]
    var id: String { hook }
}

@MainActor
@Observable
final class PluginsHooksViewModel {
    private(set) var plugins: [PluginSummary] = []
    private(set) var supportedHooks: [String] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastError: Error?

    private let client: APIClient

    init(server: URL) {
        client = APIClient(baseURL: server)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        lastError = nil
        defer { isLoading = false }

        do {
            let response = try await client.plugins()
            plugins = response.plugins ?? []
            supportedHooks = response.supportedHooks ?? []
        } catch {
            lastError = error
            errorMessage = error.localizedDescription
        }
    }

    /// Two top-level buckets — Personal (origin == "user") and Built-in
    /// (everything else). The server relays `PluginManifest.source` as `origin`:
    /// "user" (personal), "project"/"bundled"/"entrypoint"/"" (builtin/default).
    /// Plugins stay a black box: only metadata is shown, never source content.
    var originGroupedPlugins: [(title: String, plugins: [PluginSummary])] {
        let personal = plugins.filter { isPersonal($0) }
        let builtin = plugins.filter { !isPersonal($0) }

        var sections: [(title: String, plugins: [PluginSummary])] = []
        if !personal.isEmpty {
            sections.append((title: String(localized: "Personal"), plugins: personal))
        }
        if !builtin.isEmpty {
            sections.append((title: String(localized: "Built-in"), plugins: builtin))
        }
        return sections
    }

    private func isPersonal(_ plugin: PluginSummary) -> Bool {
        (plugin.origin?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) == "user"
    }

    /// Hooks grouped by name (server's `supported_hooks` order first), each
    /// listing the plugins that register it. A plugin's `hooks` array carries
    /// the names it registers.
    var groupedHooks: [HookEntry] {
        var order: [String] = supportedHooks
        var byHook: [String: [String]] = [:]

        for plugin in plugins {
            let pluginName = plugin.name ?? plugin.key ?? plugin.id
            for hook in plugin.hooks ?? [] {
                let trimmed = hook.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if !byHook.keys.contains(trimmed) {
                    byHook[trimmed] = []
                    if !order.contains(trimmed) {
                        order.append(trimmed)
                    }
                }
                byHook[trimmed, default: []].append(pluginName)
            }
        }

        return order.compactMap { hook in
            guard let providers = byHook[hook] else { return nil }
            return HookEntry(hook: hook, providers: providers.sorted())
        }
    }
}

private struct PluginRow: View {
    let plugin: PluginSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(plugin.name ?? plugin.key ?? "Unnamed Plugin")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let version = plugin.version, !version.isEmpty {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                activationBadge
            }

            if let description = plugin.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var activationBadge: some View {
        let activation = plugin.activation ?? (plugin.enabled == true ? "enabled" : "disabled")
        Text(activation.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(activation == "enabled" || activation == "provider" ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

private struct HookRow: View {
    let hook: String
    let providers: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hook)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !providers.isEmpty {
                Text(providers.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

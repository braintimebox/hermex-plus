import SwiftUI

struct SkillsView: View {
    let server: URL
    let onAPIError: (Error) -> Void

    @State private var viewModel: SkillsViewModel
    @State private var selectedSkill: SkillSummary?
    @State private var searchText = ""
    @AppStorage(SectionVisibilitySettings.collapsibleSectionsKey) private var collapsibleSections = false
    /// Expansion state per section title (only meaningful when collapsible is on).
    @State private var expandedSections: [String: Bool] = [:]

    /// Determines the initial expansion state of each origin section. With the
    /// collapsible toggle off, everything is force-expanded (flat, as before).
    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: SkillsViewModel(server: server))
    }

    /// Whether a section is expanded now. `Personal` starts open, `Built-in`
    /// starts collapsed when the collapsible feature is on; off → always open.
    private func initialExpanded(_ title: String) -> Bool {
        guard collapsibleSections else { return true }
        // Personal = first section is expanded; anything else (Built-in) collapsed.
        return title == String(localized: "Personal")
    }

    var body: some View {
        content
            .adaptiveReadableScrollContent(maxWidth: AdaptiveReadableContentWidth.secondaryDestination)
            .navigationTitle("Skills")
            .toolbar {
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
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    ForEach(filteredSections, id: \.title) { section in
                        Section {
                            originSectionContent(section)
                        } header: {
                            originSectionHeader(section.title)
                        }
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

    /// Sticky, visually distinct header for one origin section (Personal / Built-in).
    /// Always pinned while its section scrolls; carries a bold divider so the
    /// Personal→Built-in boundary is obvious in a long flat list. When the
    /// collapsible feature is on, tapping the header toggles the section.
    private func originSectionHeader(_ title: String) -> some View {
        let isExpanded = expandedSections[title] ?? initialExpanded(title)

        return Button {
            guard collapsibleSections else { return }
            expandedSections[title] = !isExpanded
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if collapsibleSections {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            // Bold boundary divider separating the two origin sections.
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func originSectionContent(_ section: (title: String, groups: [(category: String, skills: [SkillSummary])])) -> some View {
        if collapsibleSections && !(expandedSections[section.title] ?? initialExpanded(section.title)) {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                sectionGroups(section.groups)
            }
            .padding(.top, 8)
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
    @AppStorage(SectionVisibilitySettings.collapsibleSectionsKey) private var collapsibleSections = false
    @State private var expandedSections: [String: Bool] = [:]

    init(server: URL, onAPIError: @escaping (Error) -> Void) {
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: PluginsHooksViewModel(server: server))
    }

    private func initialExpanded(_ title: String) -> Bool {
        guard collapsibleSections else { return true }
        return title == String(localized: "Personal")
    }

    var body: some View {
        content
            .adaptiveReadableScrollContent(maxWidth: AdaptiveReadableContentWidth.secondaryDestination)
            .navigationTitle("Plugins / Hooks")
            .toolbar {
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
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.originGroupedPlugins, id: \.title) { section in
                                pluginOriginSection(section)
                            }
                        }
                    } header: {
                        pluginsHeader
                    }

                    hooksHeader
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

    private var pluginsHeader: some View {
        Label("Plugins", systemImage: "puzzlepiece.extension")
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var hooksHeader: some View {
        if !viewModel.groupedHooks.isEmpty {
            Label("Hooks", systemImage: "link")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Plugins", systemImage: "puzzlepiece.extension")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(viewModel.originGroupedPlugins, id: \.title) { section in
                pluginOriginSection(section)
            }
        }
    }

    /// One plugins origin bucket (Personal / Built-in): a visually distinct
    /// header (bold + divider) over its rows. Collapsible via tap when the
    /// feature is on — Personal expanded, Built-in collapsed by default.
    @ViewBuilder
    private func pluginOriginSection(_ section: (title: String, plugins: [PluginSummary])) -> some View {
        let isExpanded = expandedSections[section.title] ?? initialExpanded(section.title)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard collapsibleSections else { return }
                expandedSections[section.title] = !isExpanded
            } label: {
                HStack(spacing: 6) {
                    Text(section.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    if collapsibleSections {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if !collapsibleSections || isExpanded {
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
            VStack(alignment: .leading, spacing: 8) {
                Label("Hooks", systemImage: "link")
                    .font(.headline)
                    .foregroundStyle(.primary)

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

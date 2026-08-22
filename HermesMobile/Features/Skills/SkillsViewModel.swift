import Foundation
import Observation

@MainActor
@Observable
final class SkillsViewModel {
    private(set) var skills: [SkillSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastError: Error?
    private(set) var togglingSkillNames: Set<String> = []

    private let client: APIClient

    init(server: URL) {
        client = APIClient(baseURL: server)
    }

    init(client: APIClient) {
        self.client = client
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        lastError = nil
        defer { isLoading = false }

        do {
            let response = try await client.skills()
            skills = response.skills ?? []
        } catch {
            lastError = error
            errorMessage = error.localizedDescription
        }
    }

    var groupedSkills: [(category: String, skills: [SkillSummary])] {
        Self.groupedSkills(for: skills)
    }

    /// Two top-level buckets — Personal (origin == "user") and Built-in
    /// (everything else) — each preserving the existing per-category grouping.
    /// The server only relays `origin`; this view model splits on it so the UI
    /// never has to decide what is "mine". Order is fixed: Personal first.
    var originGroupedSections: [(title: String, groups: [(category: String, skills: [SkillSummary])])] {
        Self.originGroupedSections(for: skills)
    }

    func filteredOriginGroupedSections(searchText: String) -> [(title: String, groups: [(category: String, skills: [SkillSummary])])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return originGroupedSections }

        let filtered = skills.filter { skill in
            let name = skill.name?.localizedCaseInsensitiveContains(query) ?? false
            let description = skill.description?.localizedCaseInsensitiveContains(query) ?? false
            let category = skill.category?.localizedCaseInsensitiveContains(query) ?? false
            let tags = skill.tags?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false
            return name || description || category || tags
        }

        guard !filtered.isEmpty else { return [] }

        return Self.originGroupedSections(for: filtered)
    }

    func filteredGroupedSkills(searchText: String) -> [(category: String, skills: [SkillSummary])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groupedSkills }

        let filtered = skills.filter { skill in
            let name = skill.name?.localizedCaseInsensitiveContains(query) ?? false
            let description = skill.description?.localizedCaseInsensitiveContains(query) ?? false
            let category = skill.category?.localizedCaseInsensitiveContains(query) ?? false
            let tags = skill.tags?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false
            return name || description || category || tags
        }

        guard !filtered.isEmpty else { return [] }

        return Self.groupedSkills(for: filtered)
    }

    func setSkill(_ skill: SkillSummary, enabled: Bool) async {
        guard let name = skill.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        guard togglingSkillNames.insert(name).inserted else { return }

        lastError = nil
        errorMessage = nil
        updateSkill(named: name, disabled: !enabled)
        defer { togglingSkillNames.remove(name) }

        do {
            _ = try await client.toggleSkill(name: name, enabled: enabled)
            await load()
        } catch {
            updateSkill(named: name, disabled: enabled)
            lastError = error
            errorMessage = error.localizedDescription
        }
    }

    static func groupedSkills(for skills: [SkillSummary]) -> [(category: String, skills: [SkillSummary])] {
        let grouped = Dictionary(grouping: skills, by: categoryName(for:))
        return grouped
            .sorted {
                $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            .map { (category: $0.key, skills: sortedSkills($0.value)) }
    }

    static func originGroupedSections(for skills: [SkillSummary]) -> [(title: String, groups: [(category: String, skills: [SkillSummary])])] {
        let personal = skills.filter { isPersonal($0) }
        let builtin = skills.filter { !isPersonal($0) }

        var sections: [(title: String, groups: [(category: String, skills: [SkillSummary])])] = []
        if !personal.isEmpty {
            sections.append((title: String(localized: "Personal"), groups: groupedSkills(for: personal)))
        }
        if !builtin.isEmpty {
            sections.append((title: String(localized: "Built-in"), groups: groupedSkills(for: builtin)))
        }
        return sections
    }

    /// A skill is "personal" only when the server relays an explicit user
    /// origin. Anything else (nil, "", "user"-adjacent values only count as
    /// user at the exact match) is treated as builtin. Absent field = builtin.
    private static func isPersonal(_ skill: SkillSummary) -> Bool {
        (skill.origin?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) == "user"
    }

    private static func categoryName(for skill: SkillSummary) -> String {
        let category = skill.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category, !category.isEmpty else {
            return String(localized: "Uncategorized")
        }
        return category
    }

    private static func sortedSkills(_ skills: [SkillSummary]) -> [SkillSummary] {
        skills.sorted { lhs, rhs in
            displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    private static func displayName(for skill: SkillSummary) -> String {
        let name = skill.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else {
            return String(localized: "Unnamed Skill")
        }
        return name
    }

    private func updateSkill(named name: String, disabled: Bool) {
        skills = skills.map { skill in
            guard skill.name?.trimmingCharacters(in: .whitespacesAndNewlines) == name else { return skill }
            return SkillSummary(
                name: skill.name,
                category: skill.category,
                description: skill.description,
                path: skill.path,
                disabled: disabled,
                tags: skill.tags,
                relatedSkills: skill.relatedSkills,
                origin: skill.origin
            )
        }
    }
}

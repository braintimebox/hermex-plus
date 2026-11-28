import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    nonisolated static let emptyPasswordMessage = String(localized: "Enter the server password.")
    nonisolated static let emptyUsernameMessage = String(localized: "Enter the server username.")

    var serverURLString = "" {
        didSet { invalidateProbeIfNeeded() }
    }
    var username = ""
    var password = ""
    var customHeaders: [CustomHeader] = [] {
        didSet { invalidateProbeIfNeeded() }
    }
    var authProviders: AuthProvidersResponse?
    var connectionMessage: String?
    var errorMessage: String?
    var isWorking = false
    /// True while an operation owns the form: views disable the URL/username/password
    /// fields, header editor, and Return-key submission so a side effect that
    /// has already run (AuthManager.configure persists and activates server
    /// state) cannot be superseded by mid-flight edits (PR #294 re-gate).
    var isConnectionLocked = false

    // Identity + generation of the probe that produced `authProviders`.
    @ObservationIgnored private var probedConnectionIdentity: String?
    @ObservationIgnored private var operationGeneration = 0

    init(
        savedServer: URL? = nil,
        savedHeaders: [CustomHeader] = [],
        initialErrorMessage: String? = nil
    ) {
        if let savedServer {
            serverURLString = savedServer.absoluteString
        }
        customHeaders = savedHeaders
        errorMessage = initialErrorMessage
        if initialErrorMessage != nil {
            // The banner belongs to the restored identity so later edits clear it.
            probedConnectionIdentity = nil
        }
    }

    var isPasswordRequired: Bool {
        // The server advertises a password provider → ask for username + password.
        authProviders?.passwordProvider != nil
    }

    // MARK: - Connection identity (issue #285)

    /// Effective headers exactly as the request path would apply them:
    /// applicable rows only, case-insensitive names, array order preserved with
    /// last-write-wins for duplicate names (matches
    /// `Array<CustomHeader>.apply(to:)` via `URLRequest.setValue`). This is the
    /// credential set that actually reaches the server, so reordering duplicate
    /// names or adding/removing a newline-broken row must change it.
    private func effectiveHeaderMap() -> [(name: String, value: String)] {
        var map: [(name: String, value: String)] = []
        for header in customHeaders where header.isApplicable {
            let lowered = header.sanitizedName.lowercased()
            if let index = map.firstIndex(where: { $0.name == lowered }) {
                map[index].value = header.sanitizedValue
            } else {
                map.append((name: lowered, value: header.sanitizedValue))
            }
        }
        return map
    }

    private func currentConnectionIdentity() -> String {
        let urlPart: String
        do {
            let url = try AuthManager.normalizedServerURL(from: serverURLString)
            urlPart = url.absoluteString.lowercased()
        } catch {
            urlPart = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        // Escape delimiters so distinct header sets cannot collide, then sort
        // canonical keys for stable serialization.
        let headerPart = effectiveHeaderMap()
            .map { name, value -> String in
                "\(Self.escapeForIdentity(name)):\(Self.escapeForIdentity(value))"
            }
            .sorted()
            .joined(separator: "|")
        return "\(urlPart)|\(headerPart)"
    }

    nonisolated private static func escapeForIdentity(_ raw: String) -> String {
        var out = raw.replacingOccurrences(of: "%", with: "%25")
        out = out.replacingOccurrences(of: ":", with: "%3A")
        out = out.replacingOccurrences(of: "|", with: "%7C")
        return out
    }

    private func invalidateProbeIfNeeded() {
        guard let probed = probedConnectionIdentity else {
            // No probe yet, but an inherited banner (re-login error) still has no
            // owner — clear it on any edit so stale copy can't survive.
            if errorMessage != nil || connectionMessage != nil {
                errorMessage = nil
                connectionMessage = nil
            }
            return
        }
        let current = currentConnectionIdentity()
        if current != probed {
            authProviders = nil
            connectionMessage = nil
            errorMessage = nil
            probedConnectionIdentity = nil
        }
    }

    /// Begins a tracked async operation and returns its generation token used
    /// to fence settlement against newer overlapping operations.
    private func beginOperation() -> Int {
        operationGeneration += 1
        return operationGeneration
    }

    func testConnection(authManager: AuthManager) async {
        guard !isConnectionLocked else { return }
        errorMessage = nil
        connectionMessage = nil
        isWorking = true
        isConnectionLocked = true
        let token = beginOperation()
        let identityAtStart = currentConnectionIdentity()
        defer {
            if token == operationGeneration {
                isWorking = false
                isConnectionLocked = false
            }
        }

        do {
            let providers = try await authManager.testConnection(
                serverURLString: serverURLString,
                customHeaders: customHeaders
            )
            guard token == operationGeneration else { return }
            guard identityAtStart == currentConnectionIdentity() else { return }
            probedConnectionIdentity = identityAtStart
            authProviders = providers
            if let message = AuthManager.unsupportedSignInMessage(for: providers) {
                errorMessage = message
            } else if providers.passwordProvider != nil {
                connectionMessage = String(localized: "Connection ok. Username and password required.")
            } else {
                connectionMessage = String(localized: "Connection ok. No sign-in required.")
            }
        } catch {
            guard token == operationGeneration else { return }
            guard identityAtStart == currentConnectionIdentity() else { return }
            // A failed re-probe invalidates the prior successful result: the old
            // capability result no longer describes this identity.
            authProviders = nil
            probedConnectionIdentity = nil
            errorMessage = error.localizedDescription
        }
    }

    func connect(authManager: AuthManager) async {
        guard !isConnectionLocked else { return }
        errorMessage = nil
        connectionMessage = nil

        if let validationMessage = Self.passwordValidationMessage(
            providers: authProviders, username: username, password: password
        ) {
            errorMessage = validationMessage
            return
        }

        isWorking = true
        // Inputs stay frozen across probe AND configure: AuthManager.configure
        // persists credentials and activates the captured URL/headers as a side
        // effect, so accepting edits mid-operation would let the old server be
        // configured under a form now showing a different one (PR #294 re-gate).
        isConnectionLocked = true
        let token = beginOperation()
        defer {
            if token == operationGeneration {
                isWorking = false
                isConnectionLocked = false
            }
        }

        if authProviders == nil {
            let identityAtStart = currentConnectionIdentity()
            do {
                let providers = try await authManager.testConnection(
                    serverURLString: serverURLString,
                    customHeaders: customHeaders
                )
                guard token == operationGeneration else { return }
                guard identityAtStart == currentConnectionIdentity() else { return }
                probedConnectionIdentity = identityAtStart
                authProviders = providers
            } catch {
                guard token == operationGeneration else { return }
                guard identityAtStart == currentConnectionIdentity() else { return }
                authProviders = nil
                probedConnectionIdentity = nil
                errorMessage = error.localizedDescription
                return
            }

            if let validationMessage = Self.passwordValidationMessage(
                providers: authProviders, username: username, password: password
            ) {
                errorMessage = validationMessage
                return
            }
        } else if probedConnectionIdentity == nil {
            probedConnectionIdentity = currentConnectionIdentity()
        }

        // Fence the side effect: capture the identity configure was launched for
        // and refuse to publish its outcome under different inputs.
        let configureIdentity = currentConnectionIdentity()
        await authManager.configure(
            serverURLString: serverURLString,
            username: username,
            password: password,
            customHeaders: customHeaders
        )
        guard token == operationGeneration else { return }
        guard configureIdentity == currentConnectionIdentity() else { return }
        errorMessage = authManager.lastErrorMessage
    }

    // MARK: - Testing hooks (issue #285 regression matrix)

    func probeConnectionIdentityForTesting() -> String {
        currentConnectionIdentity()
    }

    func seedProbedIdentityForTesting() {
        probedConnectionIdentity = currentConnectionIdentity()
    }

    nonisolated static func passwordValidationMessage(
        providers: AuthProvidersResponse?, username: String, password: String
    ) -> String? {
        guard providers?.passwordProvider != nil else { return nil }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername.isEmpty { return emptyUsernameMessage }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPassword.isEmpty ? emptyPasswordMessage : nil
    }
}

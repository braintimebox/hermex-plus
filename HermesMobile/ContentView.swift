import SwiftUI

struct ContentView: View {
    @Bindable var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ResponseCompletionNotifications.isEnabledKey) private var isResponseCompletionNotificationsEnabled = false
    @State private var pendingSharedImport: SharedImportReservation?
    @State private var hasWaitingSharedImport = false
    @State private var hasRoutedSharedImport = false
    @State private var pendingDeepLinkedSessionID: String?
    @State private var pendingNewChatRequest: NewChatRequest?
    @State private var didCheckInitialPendingShare = false
    @State private var intentRouter = AppIntentRouter.shared

    var body: some View {
        content
            .onOpenURL(perform: handleOpenURL)
            .task {
                guard !didCheckInitialPendingShare else { return }
                didCheckInitialPendingShare = true
                // Cold launch: an App Intent may have queued a deep link before this
                // view appeared (e.g. Action button "New Chat"). Drain it now (#337).
                drainPendingIntentDeepLink()
            }
            .onChange(of: intentRouter.pendingDeepLink) {
                // Warm launch: the intent set the deep link after the view appeared.
                drainPendingIntentDeepLink()
            }
            .task {
                // #246: on cold launch, end any Live Activity left "running" by a
                // run that finished while the app was terminated. #248: this is also
                // the one pass allowed to fire a recent run's "response complete"
                // notification, since a relaunch means it finished while not active.
                await reconcileOrphanedLiveActivities(notifiesOnCompletion: true)
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                // #248: the foreground pass stays silent — the in-session completion
                // paths own notifications while the app is alive.
                Task { await reconcileOrphanedLiveActivities(notifiesOnCompletion: false) }
            }
    }

    private func reconcileOrphanedLiveActivities(notifiesOnCompletion: Bool) async {
        guard case let .loggedIn(server) = authManager.state else { return }
        await LiveActivityReconciler.reconcileOrphanedActivities(
            server: server,
            notifiesOnCompletion: notifiesOnCompletion,
            preferenceEnabled: isResponseCompletionNotificationsEnabled
        )
    }

    @ViewBuilder
    private var content: some View {
        switch authManager.state {
        case .unconfigured:
            OnboardingView(authManager: authManager)
        case .loggedOut(let server):
            OnboardingView(authManager: authManager, savedServer: server)
        case .loggedIn(let server):
            SessionListView(
                authManager: authManager,
                server: server,
                pendingSharedImport: $pendingSharedImport,
                didRoutePendingSharedImport: consumePendingSharedImport,
                hasWaitingSharedImport: hasWaitingSharedImport,
                openNextSharedImport: openNextSharedImport,
                pendingDeepLinkedSessionID: $pendingDeepLinkedSessionID,
                requestedNewChat: $pendingNewChatRequest
            )
            // Switching the active server keeps us in `.loggedIn`, so without a
            // per-server identity SwiftUI would reuse the same SessionListView (and
            // its server-bound view model), leaving stale sessions/chat on screen.
            // Keying on the server tears the whole stack down and rebuilds it
            // against the newly active server (#17).
            .id(server)
        }
    }

    private func handleOpenURL(_ url: URL) {
        // A fresh request each time (new `id`) so a repeat invocation re-triggers navigation
        // even if the previous one's value still lingers downstream. The voice variant carries
        // `autoStartsVoiceInput` so the composer begins dictation once it appears (#338).
        if HermesDeepLink.isNewChatVoiceURL(url) {
            pendingNewChatRequest = NewChatRequest(autoStartsVoiceInput: true)
            return
        }

        // The profile variant carries the chosen profile name, so the composer creates the
        // session pinned to it (#339). A malformed link with no profile falls back to a
        // plain new chat (server's active profile) rather than failing.
        if HermesDeepLink.isNewChatInProfileURL(url) {
            pendingNewChatRequest = NewChatRequest(
                profileName: HermesDeepLink.profileName(fromNewChatInProfile: url)
            )
            return
        }

        if HermesDeepLink.isNewChatURL(url) {
            pendingNewChatRequest = NewChatRequest(autoStartsVoiceInput: false)
            return
        }

        if let sessionID = HermesDeepLink.sessionID(from: url) {
            pendingDeepLinkedSessionID = sessionID
            return
        }

        guard HermesShareDraft.isShareOpenURL(url) else {
            return
        }

        importPendingSharedDraftIfAvailable()
    }

    /// Routes a deep link queued by an App Intent through the same `handleOpenURL` parser
    /// used for external URLs, then clears it so it routes exactly once (#337).
    private func drainPendingIntentDeepLink() {
        guard let url = intentRouter.pendingDeepLink else { return }
        intentRouter.pendingDeepLink = nil
        handleOpenURL(url)
    }

    private func importPendingSharedDraftIfAvailable() {
        guard pendingSharedImport == nil else {
            return
        }

        // HERMEX-FORK: the App Group container can be missing altogether on a
        // sideloaded build (see `saveToPasteboard` for the mechanism). Where the
        // extension falls back to the pasteboard, the app must look there too or
        // the payload is delivered and then ignored.
        guard let directory = HermesShareDraft.containerURL() else {
            // HERMEX-FORK: no App Group container means the payload can only be
            // sitting on the fallback pasteboard.
            reservePasteboardSharedImportIfAvailable()
            return
        }

        guard !hasRoutedSharedImport else {
            refreshWaitingSharedImport(in: directory)
            return
        }

        do {
            pendingSharedImport = try HermesShareDraft.reserveNextPendingImport(from: directory)
            // HERMEX-FORK: the App Group inbox only wins when it actually had
            // something; an empty inbox means the share may have travelled on
            // the fallback pasteboard instead.
            if let reservation = pendingSharedImport {
                logSharedImportSource(reservation.source)
            } else {
                reservePasteboardSharedImportIfAvailable()
            }
            refreshWaitingSharedImport(in: directory)
        } catch {
            pendingSharedImport = nil
            hasWaitingSharedImport = false
            reservePasteboardSharedImportIfAvailable()
        }
    }

    /// HERMEX-FORK: claims a payload from the fallback transport. Also the place
    /// where a share that reached neither transport is recorded — an empty inbox
    /// plus an empty pasteboard used to look exactly like a share that never
    /// arrived, which is what made this failure invisible for so long.
    private func reservePasteboardSharedImportIfAvailable() {
        guard let reservation = HermesShareDraft.reserveNextPasteboardImport() else {
            hasWaitingSharedImport = false
            logSharedImportSource(.unavailable)
            return
        }

        pendingSharedImport = reservation
        hasWaitingSharedImport = false
        logSharedImportSource(reservation.source)
    }

    /// HERMEX-FORK: names the transport a share arrived on. Without this line the
    /// two transports are indistinguishable from the outside, and "sharing
    /// degraded" has no evidence attached to it.
    private func logSharedImportSource(_ source: ShareDeliverySource) {
        HermexLogger.shared.log(
            type: "event",
            screen: "ShareImport",
            message: "share received",
            extras: [
                "source": source.rawValue,
                "detail": source.diagnosticsDetail
            ]
        )
    }

    private func consumePendingSharedImport(_ reservation: SharedImportReservation) {
        hasRoutedSharedImport = true

        defer {
            if pendingSharedImport?.reservationID == reservation.reservationID {
                pendingSharedImport = nil
            }
        }

        guard let directory = HermesShareDraft.containerURL() else {
            return
        }

        do {
            try HermesShareDraft.consume(reservation, from: directory)
        } catch {
            // Keep the share recoverable if acknowledgement fails after routing.
            try? HermesShareDraft.release(reservation, in: directory)
        }
        refreshWaitingSharedImport(in: directory)
    }

    private func openNextSharedImport() {
        hasWaitingSharedImport = false
        hasRoutedSharedImport = false
        importPendingSharedDraftIfAvailable()
    }

    private func refreshWaitingSharedImport(in directory: URL) {
        hasWaitingSharedImport = (try? HermesShareDraft.hasPendingImport(in: directory)) ?? false
    }
}

#Preview {
    ContentView(authManager: AuthManager())
}

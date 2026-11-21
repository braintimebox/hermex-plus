import UIKit

@MainActor
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private var didStartOpening = false
    /// Text carried inside the open URL. Nothing is written to disk on that
    /// path, so if the app does not open the text has no other home.
    private var inlineDraft: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard !didStartOpening else { return }
        didStartOpening = true

        Task {
            await saveDraftAndOpenHermes()
        }
    }

    private func configureView() {
        view.backgroundColor = .clear
        view.isOpaque = false

        statusLabel.text = "Opening Hermex..."
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func saveDraftAndOpenHermes() async {
        let input = await ShareInputReader.input(from: extensionContext)
        let draft = HermesShareDraft.draftText(textSnippets: input.textSnippets, urls: input.urls)

        guard !draft.isEmpty || !input.attachments.isEmpty else {
            showStatus("Hermex accepts text, URLs, images, PDFs, and files up to 20 MB.")
            completeRequest(after: 0.8)
            return
        }

        // Text-only share that fits the URL: hand the draft over inline, exactly
        // as 3.6.0 did. The system carries the payload to the containing app, so
        // neither the shared container nor a named pasteboard is involved — and
        // both of those are App-Group scoped, which a re-signed sideloaded
        // extension does not have. This is the path that actually worked before
        // 3.7.0 removed it.
        let fitsInline = input.attachments.isEmpty
            && draft.utf8.count <= HermesShareDraft.maximumURLDraftBytes

        if fitsInline {
            inlineDraft = draft
            openHermes(withDraft: draft)
            return
        }

        // HERMEX-FORK: a named pasteboard is not a guaranteed second chance on a
        // re-signed build — Apple scopes named boards to the signing identity, and
        // a sideloader's identity is not the one the App Group was issued for.
        // When neither it nor the container delivers, the text still has a
        // transport that needs no entitlement at all: the general board.
        // Attachments cannot follow it, and the user is told so instead of the
        // payload vanishing.
        var containerDelivered = false

        if let directory = HermesShareDraft.containerURL() {
            do {
                try HermesShareDraft.savePendingImport(
                    draft: draft,
                    attachments: input.attachments,
                    in: directory
                )
                containerDelivered = true
            } catch {
                containerDelivered = false
            }
        }

        let namedPasteboardDelivered = HermesShareDraft.saveToPasteboard(
            draft: draft,
            attachments: input.attachments
        )

        var generalPasteboardDelivered = false
        if !containerDelivered, !namedPasteboardDelivered {
            generalPasteboardDelivered = HermesShareDraft.saveTextToGeneralPasteboard(draft)
        }

        let outcome = HermesShareDraft.deliveryOutcome(
            containerDelivered: containerDelivered,
            namedPasteboardDelivered: namedPasteboardDelivered,
            generalPasteboardDelivered: generalPasteboardDelivered
        )

        if let message = HermesShareDraft.statusMessage(forDelivery: outcome) {
            showStatus(message)
        }

        // Nothing was carried: do not open the app or claim success.
        guard outcome != .unavailable else {
            completeRequest(after: 1.5)
            return
        }

        openHermes()
    }

    private func showStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.isHidden = false
    }

    private func openHermes(withDraft draft: String) {
        openHermes(at: HermesShareDraft.openURL(withDraft: draft))
    }

    private func openHermes() {
        openHermes(at: HermesShareDraft.openURL)
    }

    private func openHermes(at url: URL) {
        extensionContext?.open(url, completionHandler: { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if success {
                    self.finishOpen(.confirmed)
                } else {
                    self.openHermesViaWorkaround(url)
                }
            }
        })
    }

    /// Dispatches the request through the fallback paths. None of them can
    /// observe whether the containing app actually opened — the API behind them
    /// returns no result — so the best any path may report is `.dispatchedOnly`.
    /// Calling that "opened" was the false success this replaces.
    private func openHermesViaWorkaround(_ url: URL) {
        if let application = containingApplicationResponder(),
           dispatchOpen(url, using: application) {
            finishOpen(.dispatchedOnly)
            return
        }

        if dispatchOpenViaResponderChain(url) || dispatchOpenViaContainingApplication(url) {
            finishOpen(.dispatchedOnly)
            return
        }

        finishOpen(.failed)
    }

    /// Single place that turns an outcome into UI: only a confirmed open leaves
    /// without a message.
    private func finishOpen(_ outcome: HermesShareDraft.ShareOpenOutcome) {
        if outcome == .confirmed {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        // The inline path wrote nothing to disk. Before telling the user to open
        // the app by hand, put the text somewhere they can retrieve it.
        if let draft = inlineDraft,
           HermesShareDraft.saveTextToGeneralPasteboard(draft) {
            showStatus("Open Hermex manually. The text was copied — paste it there.")
        } else if let message = HermesShareDraft.statusMessage(forOpen: outcome) {
            showStatus(message)
        }

        completeRequest(after: 1.5)
    }

    /// Sends the open request through the application object. Returns `true`
    /// when the request was dispatched — not when the app opened; the selector
    /// is called with a nil completion, so no result exists to report.
    private func dispatchOpenViaContainingApplication(_ url: URL) -> Bool {
        // Owner-accepted App Review risk: share extensions have no guaranteed
        // containing-app launcher, but this preserves the current fast return UX.
        let sharedApplicationSelector = NSSelectorFromString("sharedApplication")
        let openURLModernSelector = NSSelectorFromString("openURL:options:completionHandler:")

        guard
            let applicationClass = NSClassFromString("UIApplication") as? NSObject.Type,
            applicationClass.responds(to: sharedApplicationSelector),
            let application = applicationClass.perform(sharedApplicationSelector)?.takeUnretainedValue() as? NSObject
        else {
            return false
        }

        if application.responds(to: openURLModernSelector),
           let implementation = application.method(for: openURLModernSelector) {
            typealias OpenURLModernFunction = @convention(c) (NSObject, Selector, NSURL, NSDictionary, Any?) -> Void
            let openURL = unsafeBitCast(implementation, to: OpenURLModernFunction.self)
            openURL(application, openURLModernSelector, url as NSURL, [:] as NSDictionary, nil)
            return true
        }

        return false
    }

    private func containingApplicationResponder() -> UIResponder? {
        guard let applicationClass = NSClassFromString("UIApplication") else {
            return nil
        }

        var responder: UIResponder? = self
        while let currentResponder = responder {
            if currentResponder.isKind(of: applicationClass) {
                return currentResponder
            }

            responder = currentResponder.next
        }

        return nil
    }

    /// Walks the responder chain dispatching the request. Returns `true` when at
    /// least one responder accepted the dispatch, which is not proof of opening.
    private func dispatchOpenViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if dispatchOpen(url, using: currentResponder) {
                return true
            }

            responder = currentResponder.next
        }

        return false
    }

    private func dispatchOpen(_ url: URL, using responder: UIResponder) -> Bool {
        // Owner-accepted App Review risk; this is a fallback for hosts where
        // NSExtensionContext.open does not route to the containing app. The
        // completion is nil, so `true` means "dispatched", never "opened".
        if let application = responder as? UIApplication {
            application.open(url, options: [:], completionHandler: nil)
            return true
        }

        let openURLModernSelector = NSSelectorFromString("openURL:options:completionHandler:")
        if responder.responds(to: openURLModernSelector),
           let implementation = responder.method(for: openURLModernSelector) {
            typealias OpenURLModernFunction = @convention(c) (UIResponder, Selector, NSURL, NSDictionary, Any?) -> Void
            let openURL = unsafeBitCast(implementation, to: OpenURLModernFunction.self)
            openURL(responder, openURLModernSelector, url as NSURL, [:] as NSDictionary, nil)
            return true
        }

        return false
    }

    private func completeRequest(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}

import AppKit
import StoreKit

/// Subscription paywall shown when the app is not unlocked.
/// Apple review requires the paywall to link to a privacy policy and
/// terms of use, so keep those buttons in place.
class PaywallWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var monthlyBtn: NSButton!
    private var yearlyBtn: NSButton!
    private var restoreBtn: NSButton!
    private var statusLabel: NSTextField!

    static let privacyPolicyURL = URL(string: "https://harveycreative.co/screendivider/privacy.html")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var onUnlocked: (() -> Void)?

    func show() {
        if window == nil {
            buildWindow()
            SubscriptionManager.shared.onProductsLoaded = { [weak self] _ in
                self?.updateProductButtons()
            }
        }
        updateProductButtons()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Screen Divider"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        let content = window.contentView!
        let m: CGFloat = 34

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(iconView)

        let title = NSTextField(labelWithString: "Unlock Screen Divider")
        title.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Snap windows into your own custom zones on every display. Drag any window and drop it exactly where it belongs.")
        subtitle.font = NSFont.systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subtitle)

        monthlyBtn = NSButton(title: "Monthly", target: self, action: #selector(buyMonthly))
        yearlyBtn = NSButton(title: "Yearly", target: self, action: #selector(buyYearly))
        for btn in [monthlyBtn!, yearlyBtn!] {
            btn.bezelStyle = .rounded
            btn.controlSize = .large
            btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            btn.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(btn)
        }
        yearlyBtn.keyEquivalent = "\r"

        statusLabel = NSTextField(labelWithString: "Loading plans from the App Store...")
        statusLabel.font = NSFont.systemFont(ofSize: 11.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        restoreBtn = NSButton(title: "Restore Purchases", target: self, action: #selector(restore))
        restoreBtn.bezelStyle = .inline
        restoreBtn.isBordered = false
        restoreBtn.font = NSFont.systemFont(ofSize: 11.5)
        restoreBtn.contentTintColor = .linkColor
        restoreBtn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(restoreBtn)

        let privacyBtn = NSButton(title: "Privacy Policy", target: self, action: #selector(openPrivacy))
        let termsBtn = NSButton(title: "Terms of Use", target: self, action: #selector(openTerms))
        for btn in [privacyBtn, termsBtn] {
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 10.5)
            btn.contentTintColor = .tertiaryLabelColor
            btn.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(btn)
        }

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            iconView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 76),
            iconView.heightAnchor.constraint(equalToConstant: 76),

            title.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            subtitle.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            yearlyBtn.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22),
            yearlyBtn.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            yearlyBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            monthlyBtn.topAnchor.constraint(equalTo: yearlyBtn.bottomAnchor, constant: 8),
            monthlyBtn.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            monthlyBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            statusLabel.topAnchor.constraint(equalTo: monthlyBtn.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            restoreBtn.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            restoreBtn.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            privacyBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            privacyBtn.trailingAnchor.constraint(equalTo: content.centerXAnchor, constant: -8),
            termsBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            termsBtn.leadingAnchor.constraint(equalTo: content.centerXAnchor, constant: 8),
        ])
    }

    // MARK: - Product display

    private func updateProductButtons() {
        let mgr = SubscriptionManager.shared
        guard !mgr.products.isEmpty else {
            monthlyBtn.isEnabled = false
            yearlyBtn.isEnabled = false
            return
        }
        monthlyBtn.isEnabled = true
        yearlyBtn.isEnabled = true

        for product in mgr.products {
            let period = product.id == SubscriptionManager.monthlyProductID ? "month" : "year"
            var label = "\(product.displayPrice) / \(period)"
            if let intro = product.subscription?.introductoryOffer, intro.paymentMode == .freeTrial {
                label = "\(trialText(intro.period)) free, then \(label)"
            }
            if product.id == SubscriptionManager.monthlyProductID {
                monthlyBtn.title = label
            } else {
                yearlyBtn.title = "\(label) — best value"
            }
        }
        statusLabel.stringValue = "Auto-renews until cancelled. Cancel anytime in App Store settings."
    }

    private func trialText(_ period: Product.SubscriptionPeriod) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        if period.value == 1, period.unit == .week { return "7 days" }
        return "\(period.value) \(unit)\(period.value == 1 ? "" : "s")"
    }

    // MARK: - Actions

    @objc private func buyMonthly() { buy(id: SubscriptionManager.monthlyProductID) }
    @objc private func buyYearly() { buy(id: SubscriptionManager.yearlyProductID) }

    private func buy(id: String) {
        guard let product = SubscriptionManager.shared.products.first(where: { $0.id == id }) else { return }
        setBusy(true, message: "Contacting the App Store...")
        Task { @MainActor [weak self] in
            do {
                let purchased = try await SubscriptionManager.shared.purchase(product)
                self?.setBusy(false, message: purchased ? "Purchase complete!" : "")
                if purchased {
                    self?.onUnlocked?()
                    self?.window?.close()
                } else {
                    self?.updateProductButtons()
                }
            } catch {
                self?.setBusy(false, message: "Purchase failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func restore() {
        setBusy(true, message: "Restoring purchases...")
        Task { @MainActor [weak self] in
            do {
                try await SubscriptionManager.shared.restorePurchases()
                if SubscriptionManager.shared.isSubscribed {
                    self?.setBusy(false, message: "Subscription restored!")
                    self?.onUnlocked?()
                    self?.window?.close()
                } else {
                    self?.setBusy(false, message: "No active subscription found for this Apple ID.")
                    self?.updateProductButtons()
                }
            } catch {
                self?.setBusy(false, message: "Restore failed: \(error.localizedDescription)")
            }
        }
    }

    private func setBusy(_ busy: Bool, message: String) {
        monthlyBtn.isEnabled = !busy
        yearlyBtn.isEnabled = !busy
        restoreBtn.isEnabled = !busy
        statusLabel.stringValue = message
    }

    @objc private func openPrivacy() { NSWorkspace.shared.open(Self.privacyPolicyURL) }
    @objc private func openTerms() { NSWorkspace.shared.open(Self.termsURL) }
}

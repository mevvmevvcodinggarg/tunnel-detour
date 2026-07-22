import AppKit
import TunnelDetourCore

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
final class MainWindowController: NSWindowController {
    private static let sponsorPromptDefaultsKey = "sponsorPromptState.v1"
    private let store: ConfigStore
    private var config: TunnelDetourConfig

    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: AppStatus.ready.rawValue)
    private let progressIndicator = NSProgressIndicator()
    private let sidebarStatusDot = NSView()
    private let sidebarStatusLabel = NSTextField(labelWithString: AppStatus.ready.rawValue)
    private let wifiField = NSTextField()
    private let publicDNSField = NSTextField()
    private let privateHostField = NSTextField()
    private let googleServicesCheckbox = NSButton(
        checkboxWithTitle: "Google Services Direct",
        target: nil,
        action: nil
    )
    private let adaptiveCheckbox = NSButton(
        checkboxWithTitle: "Adaptive Direct Sites",
        target: nil,
        action: nil
    )
    private let serviceSearchField = NSSearchField()
    private let serviceListStack = FlippedStackView()
    private var serviceCheckboxes: [String: NSButton] = [:]
    private let siteSearchField = NSSearchField()
    private let siteRouteStatusLabel = NSTextField(labelWithString: "")
    private let domainsTextView = NSTextView()
    private let ipv4TextView = NSTextView()
    private let logTextView = NSTextView()
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let verifyButton = NSButton(title: "Verify", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let checkSiteButton = NSButton(title: "Check", target: nil, action: nil)
    private let addSiteButton = NSButton(title: "Add", target: nil, action: nil)
    private let repairSiteButton = NSButton(title: "Repair", target: nil, action: nil)
    private let settingsButton = NSButton(title: "", target: nil, action: nil)
    private let moreButton = NSButton(title: "", target: nil, action: nil)
    private let activityDisclosureButton = NSButton(title: "Activity", target: nil, action: nil)
    private let activityContainer = NSStackView()
    private var settingsPopover: NSPopover?
    private var restoreMenuItem: NSMenuItem?
    private var removeHelperMenuItem: NSMenuItem?

    private let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
        self.config = (try? store.load()) ?? .defaults

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TunnelDetour"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.center()

        super.init(window: window)
        buildInterface()
        loadConfigIntoControls()
        setStatus(.ready)
        appendLog(ActivityMessage.ready)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active

        let workspace = NSView()
        workspace.wantsLayer = true
        workspace.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(workspace)
        sidebar.widthAnchor.constraint(equalToConstant: TunnelDetourTheme.sidebarWidth).isActive = true
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        buildSidebar(in: sidebar)
        buildWorkspace(in: workspace)
        configureButtons()
        rebuildServiceSidebar()
    }

    private func buildSidebar(in sidebar: NSVisualEffectView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: TunnelDetourTheme.contentInset),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -TunnelDetourTheme.contentInset),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: TunnelDetourTheme.contentInset),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -TunnelDetourTheme.contentInset)
        ])

        let title = NSTextField(labelWithString: "TunnelDetour")
        title.font = TunnelDetourTheme.titleFont
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Direct services")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        stack.addArrangedSubview(titleStack)
        stack.addArrangedSubview(makeSidebarStatusRow())

        serviceSearchField.placeholderString = "Search services"
        serviceSearchField.sendsSearchStringImmediately = true
        serviceSearchField.target = self
        serviceSearchField.action = #selector(serviceSearchChanged)
        serviceSearchField.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(serviceSearchField)
        serviceSearchField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let serviceScrollView = makeServiceScrollView()
        serviceScrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        serviceScrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(serviceScrollView)
        serviceScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        serviceScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    }

    private func makeStatusRow() -> NSView {
        configureStatusDot(statusDot)

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16)
        ])

        let stack = NSStackView(views: [statusDot, progressIndicator, statusLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func makeSidebarStatusRow() -> NSView {
        configureStatusDot(sidebarStatusDot)
        sidebarStatusLabel.font = TunnelDetourTheme.compactFont
        sidebarStatusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [sidebarStatusDot, sidebarStatusLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func configureStatusDot(_ dot: NSView) {
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10)
        ])
    }

    private func makeServiceScrollView() -> NSScrollView {
        serviceListStack.orientation = .vertical
        serviceListStack.alignment = .leading
        serviceListStack.spacing = 5
        serviceListStack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 8, right: 0)
        serviceListStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = serviceListStack

        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            serviceListStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            serviceListStack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            serviceListStack.topAnchor.constraint(equalTo: clipView.topAnchor),
            serviceListStack.widthAnchor.constraint(equalTo: clipView.widthAnchor)
        ])
        return scrollView
    }

    @objc private func serviceSearchChanged() {
        rebuildServiceSidebar()
    }

    private func rebuildServiceSidebar() {
        serviceListStack.arrangedSubviews.forEach {
            serviceListStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let groups = ServiceFilter.matchingGroups(
            TunnelDetourConfig.serviceGroups,
            query: serviceSearchField.stringValue
        )
        var previousCategory: String?
        for group in groups {
            if group.category != previousCategory {
                let label = NSTextField(labelWithString: group.category)
                label.font = TunnelDetourTheme.compactFont
                label.textColor = .secondaryLabelColor
                serviceListStack.addArrangedSubview(label)
                previousCategory = group.category
            }

            let checkbox: NSButton
            if let existing = serviceCheckboxes[group.id] {
                checkbox = existing
            } else {
                checkbox = NSButton(
                    checkboxWithTitle: group.name,
                    target: self,
                    action: #selector(serviceSelectionChanged)
                )
                checkbox.state = config.enabledServiceIDs.contains(group.id) ? .on : .off
                serviceCheckboxes[group.id] = checkbox
            }
            checkbox.title = group.name
            checkbox.toolTip = group.domains.joined(separator: ", ")
            serviceListStack.addArrangedSubview(checkbox)
        }
    }

    private func buildWorkspace(in workspace: NSView) {
        let actionBar = makeActionBar()
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(actionBar)

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        workspace.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: workspace.leadingAnchor, constant: TunnelDetourTheme.contentInset),
            contentStack.trailingAnchor.constraint(equalTo: workspace.trailingAnchor, constant: -TunnelDetourTheme.contentInset),
            contentStack.topAnchor.constraint(equalTo: workspace.topAnchor, constant: TunnelDetourTheme.contentInset),
            contentStack.bottomAnchor.constraint(equalTo: actionBar.topAnchor, constant: -TunnelDetourTheme.sectionSpacing),
            actionBar.leadingAnchor.constraint(equalTo: workspace.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: workspace.trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: workspace.bottomAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 52)
        ])

        contentStack.addArrangedSubview(makeWorkspaceHeader())
        contentStack.setCustomSpacing(TunnelDetourTheme.sectionSpacing, after: contentStack.arrangedSubviews.last!)

        contentStack.addArrangedSubview(makeSectionTitle("Direct Sites"))
        contentStack.addArrangedSubview(makeSiteSearchRow())
        let domainEditor = configuredScrollView(textView: domainsTextView, editable: true)
        domainEditor.setContentHuggingPriority(.defaultLow, for: .vertical)
        domainEditor.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        contentStack.addArrangedSubview(domainEditor)
        domainEditor.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        domainEditor.heightAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        contentStack.setCustomSpacing(TunnelDetourTheme.sectionSpacing, after: domainEditor)

        contentStack.addArrangedSubview(makeSectionTitle("Direct IPs"))
        let ipEditor = configuredScrollView(textView: ipv4TextView, editable: true)
        contentStack.addArrangedSubview(ipEditor)
        ipEditor.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        ipEditor.heightAnchor.constraint(equalToConstant: 72).isActive = true
        contentStack.setCustomSpacing(TunnelDetourTheme.sectionSpacing, after: ipEditor)

        configureActivitySection()
        contentStack.addArrangedSubview(activityDisclosureButton)
        activityDisclosureButton.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.addArrangedSubview(activityContainer)
        activityContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        activityContainer.heightAnchor.constraint(equalToConstant: 96).isActive = true
        setActivityExpanded(false)
    }

    private func makeWorkspaceHeader() -> NSView {
        let title = NSTextField(labelWithString: "Direct Routes")
        title.font = TunnelDetourTheme.titleFont
        title.textColor = .labelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        settingsButton.toolTip = "Settings"
        settingsButton.setAccessibilityLabel("Settings")

        let stack = NSStackView(views: [title, spacer, makeStatusRow(), settingsButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeSettingsPopover() -> NSView {
        configureTextField(wifiField)
        configureTextField(publicDNSField)
        configureTextField(privateHostField)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(makeFormRow(label: "Wi-Fi Interface", control: wifiField))
        stack.addArrangedSubview(makeFormRow(label: "Public DNS", control: publicDNSField))
        stack.addArrangedSubview(makeFormRow(label: "Private Check (optional)", control: privateHostField))
        googleServicesCheckbox.toolTip = "Uses Google service ranges while excluding Google Cloud customer ranges."
        stack.addArrangedSubview(makeFormRow(label: "Streaming", control: googleServicesCheckbox))
        adaptiveCheckbox.toolTip = "Keeps changing service addresses on the selected connection path."
        stack.addArrangedSubview(makeFormRow(label: "Automation", control: adaptiveCheckbox))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 224))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: TunnelDetourTheme.contentInset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -TunnelDetourTheme.contentInset),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: TunnelDetourTheme.contentInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -TunnelDetourTheme.contentInset)
        ])
        return container
    }

    private func makeFormRow(label title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 126).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityLabel(title)
        control.widthAnchor.constraint(equalToConstant: 294).isActive = true

        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private func makeSectionTitle(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = TunnelDetourTheme.sectionFont
        label.textColor = .labelColor
        return label
    }

    private func makeSiteSearchRow() -> NSView {
        siteSearchField.placeholderString = "Paste a site, IP, or request URL"
        siteSearchField.sendsWholeSearchString = true
        siteSearchField.target = self
        siteSearchField.action = #selector(checkSite)
        siteSearchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        siteSearchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        checkSiteButton.translatesAutoresizingMaskIntoConstraints = false
        checkSiteButton.widthAnchor.constraint(equalToConstant: 68).isActive = true
        addSiteButton.translatesAutoresizingMaskIntoConstraints = false
        addSiteButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        repairSiteButton.translatesAutoresizingMaskIntoConstraints = false
        repairSiteButton.widthAnchor.constraint(equalToConstant: 78).isActive = true
        repairSiteButton.toolTip = "Refresh the connection for the pasted URL, host, or IP."

        siteRouteStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        siteRouteStatusLabel.textColor = .secondaryLabelColor
        siteRouteStatusLabel.lineBreakMode = .byTruncatingTail
        siteRouteStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        siteRouteStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let stack = NSStackView(views: [
            siteSearchField,
            checkSiteButton,
            addSiteButton,
            repairSiteButton,
            siteRouteStatusLabel
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeActionBar() -> NSView {
        moreButton.toolTip = "More"
        moreButton.setAccessibilityLabel("More")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [applyButton, verifyButton, saveButton, resetButton, spacer, moreButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSView()
        bar.addSubview(separator)
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: TunnelDetourTheme.contentInset),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -TunnelDetourTheme.contentInset),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: 1)
        ])
        return bar
    }

    private func configureTextField(_ field: NSTextField) {
        field.font = NSFont.systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.bezelStyle = .roundedBezel
    }

    private func configuredScrollView(textView: NSTextView, editable: Bool) -> NSScrollView {
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.isEditable = editable
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = editable ? .textBackgroundColor : NSColor.windowBackgroundColor
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        return scrollView
    }

    private func configureActivitySection() {
        activityDisclosureButton.setButtonType(.onOff)
        activityDisclosureButton.bezelStyle = .inline
        activityDisclosureButton.font = TunnelDetourTheme.sectionFont
        activityDisclosureButton.alignment = .left
        activityDisclosureButton.imagePosition = .imageLeading
        activityDisclosureButton.imageScaling = .scaleProportionallyDown
        activityDisclosureButton.target = self
        activityDisclosureButton.action = #selector(toggleActivity)

        activityContainer.orientation = .vertical
        activityContainer.alignment = .leading
        let logScrollView = configuredScrollView(textView: logTextView, editable: false)
        activityContainer.addArrangedSubview(logScrollView)
        logScrollView.widthAnchor.constraint(equalTo: activityContainer.widthAnchor).isActive = true
    }

    @objc private func toggleActivity() {
        setActivityExpanded(activityDisclosureButton.state == .on)
    }

    private func setActivityExpanded(_ expanded: Bool) {
        activityDisclosureButton.state = expanded ? .on : .off
        activityDisclosureButton.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        activityContainer.isHidden = !expanded
    }

    @objc private func showSettings(_ sender: NSButton) {
        let popover: NSPopover
        if let settingsPopover {
            popover = settingsPopover
        } else {
            popover = NSPopover()
            popover.behavior = .transient
            let viewController = NSViewController()
            viewController.view = makeSettingsPopover()
            popover.contentViewController = viewController
            settingsPopover = popover
        }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func configureButtons() {
        configureButton(applyButton, symbol: "arrow.triangle.2.circlepath", action: #selector(applyRoutes))
        configureButton(verifyButton, symbol: "checkmark.shield", action: #selector(verifyRoutes))
        configureButton(saveButton, symbol: "square.and.arrow.down", action: #selector(saveSettings))
        configureButton(resetButton, symbol: "arrow.counterclockwise", action: #selector(resetDefaults))
        configureButton(checkSiteButton, symbol: "magnifyingglass", action: #selector(checkSite))
        configureButton(addSiteButton, symbol: "plus", action: #selector(quickAddSite))
        configureButton(repairSiteButton, symbol: "arrow.clockwise", action: #selector(repairSite))
        configureButton(settingsButton, symbol: "gearshape", action: #selector(showSettings(_:)))
        configureButton(moreButton, symbol: "ellipsis.circle", action: #selector(showMoreMenu))
        applyButton.keyEquivalent = "\r"
        applyButton.keyEquivalentModifierMask = []

        let menu = NSMenu()
        let restoreItem = menu.addItem(
            withTitle: "Restore Network",
            action: #selector(restoreNetwork),
            keyEquivalent: ""
        )
        restoreItem.target = self
        restoreMenuItem = restoreItem
        let removeItem = menu.addItem(
            withTitle: "Remove Helper",
            action: #selector(removeHelper),
            keyEquivalent: ""
        )
        removeItem.target = self
        removeHelperMenuItem = removeItem
        let sponsorItem = menu.addItem(
            withTitle: "Support TunnelDetour…",
            action: #selector(openSponsorPage),
            keyEquivalent: ""
        )
        sponsorItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(
            withTitle: "Quit TunnelDetour",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        moreButton.menu = menu
    }

    @objc private func showMoreMenu() {
        moreButton.menu?.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: moreButton.bounds.maxY),
            in: moreButton
        )
    }

    private func configureButton(_ button: NSButton, symbol: String, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 13, weight: button == applyButton ? .semibold : .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
    }

    private func loadConfigIntoControls() {
        wifiField.stringValue = config.wifiInterface
        publicDNSField.stringValue = config.publicDNS.joined(separator: ", ")
        privateHostField.stringValue = config.privateCheckHost
        googleServicesCheckbox.state = config.googleServicesDirect ? .on : .off
        adaptiveCheckbox.state = config.adaptiveDirectSites ? .on : .off
        for (id, checkbox) in serviceCheckboxes {
            checkbox.state = config.enabledServiceIDs.contains(id) ? .on : .off
        }
        domainsTextView.string = config.customDomainTargets.map(\.value).joined(separator: "\n")
        ipv4TextView.string = config.ipv4Targets.map(\.value).joined(separator: "\n")
        rebuildServiceSidebar()
    }

    private func setStatus(_ status: AppStatus) {
        statusLabel.stringValue = status.rawValue
        sidebarStatusLabel.stringValue = status.rawValue
        let color: NSColor
        switch status {
        case .ready:
            color = .systemGray
        case .needsApply:
            color = .systemOrange
        case .applying:
            color = .systemBlue
        case .verified:
            color = .systemGreen
        case .error:
            color = .systemRed
        }
        statusDot.layer?.backgroundColor = color.cgColor
        sidebarStatusDot.layer?.backgroundColor = color.cgColor
    }

    @objc private func saveSettings() {
        do {
            _ = try saveConfigFromControls()
            setStatus(.needsApply)
            appendLog(ActivityMessage.saved)
        } catch {
            handleError(error)
        }
    }

    @objc private func serviceSelectionChanged() {
        setStatus(.needsApply)
    }

    @objc private func resetDefaults() {
        config = .defaults
        loadConfigIntoControls()
        do {
            try store.save(config)
            setStatus(.needsApply)
            appendLog(ActivityMessage.restored)
        } catch {
            handleError(error)
        }
    }

    @objc private func applyRoutes() {
        let savedConfig: TunnelDetourConfig
        do {
            savedConfig = try saveConfigFromControls()
        } catch {
            handleError(error)
            return
        }

        setBusy(true)
        setStatus(.applying)
        appendLog(ActivityMessage.applying)

        Task.detached {
            do {
                _ = try RouteManager.apply(config: savedConfig)
                await MainActor.run {
                    self.appendLog(ActivityMessage.applied)
                    self.setStatus(.verified)
                    self.setBusy(false)
                    self.recordSuccessfulApplyAndMaybePrompt()
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                    self.setBusy(false)
                }
            }
        }
    }

    @objc private func verifyRoutes() {
        let savedConfig: TunnelDetourConfig
        do {
            savedConfig = try saveConfigFromControls()
        } catch {
            handleError(error)
            return
        }

        setBusy(true)
        setStatus(.applying)
        appendLog(ActivityMessage.checking)

        Task.detached {
            do {
                _ = try RouteManager.verify(config: savedConfig)
                await MainActor.run {
                    self.appendLog(ActivityMessage.checked)
                    self.setStatus(.verified)
                    self.setBusy(false)
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                    self.setBusy(false)
                }
            }
        }
    }

    @objc private func checkSite() {
        guard let target = RouteManager.directTarget(for: siteSearchField.stringValue) else {
            updateSiteRouteStatus(.unavailable, isListed: false)
            return
        }

        let directInterface = wifiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let interface = directInterface.isEmpty ? TunnelDetourConfig.defaults.wifiInterface : directInterface
        let isListed = isTargetListed(target)
        setBusy(true)
        siteRouteStatusLabel.stringValue = "Checking"
        siteRouteStatusLabel.textColor = .secondaryLabelColor

        Task.detached {
            let state = (try? RouteManager.siteRouteState(
                for: target.value,
                directInterface: interface
            )) ?? .unavailable
            await MainActor.run {
                self.updateSiteRouteStatus(state, isListed: isListed)
                self.setBusy(false)
            }
        }
    }

    @objc private func quickAddSite() {
        guard let target = RouteManager.directTarget(for: siteSearchField.stringValue) else {
            updateSiteRouteStatus(.unavailable, isListed: false)
            return
        }

        if isTargetListed(target) {
            siteRouteStatusLabel.stringValue = "Already listed"
            siteRouteStatusLabel.textColor = .secondaryLabelColor
            return
        }

        switch target.kind {
        case .domain:
            var values = parseLines(domainsTextView.string)
            values.append(target.value)
            domainsTextView.string = unique(values).joined(separator: "\n")
        case .ipv4:
            var values = parseLines(ipv4TextView.string)
            values.append(target.value)
            ipv4TextView.string = unique(values).joined(separator: "\n")
        }

        do {
            _ = try saveConfigFromControls()
            setStatus(.needsApply)
            siteRouteStatusLabel.stringValue = "Added | Apply"
            siteRouteStatusLabel.textColor = .systemOrange
            appendLog(ActivityMessage.saved)
        } catch {
            handleError(error)
        }
    }

    @objc private func repairSite() {
        let input = siteSearchField.stringValue
        guard let target = RouteManager.directTarget(for: input) else {
            updateSiteRouteStatus(.unavailable, isListed: false)
            return
        }

        let enteredInterface = wifiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let interface = enteredInterface.isEmpty
            ? TunnelDetourConfig.defaults.wifiInterface
            : enteredInterface
        let enteredDNS = unique(parseTokens(publicDNSField.stringValue).filter(RouteManager.isIPv4))
        let publicDNS = enteredDNS.isEmpty ? TunnelDetourConfig.defaults.publicDNS : enteredDNS
        let isListed = isTargetListed(target)

        setBusy(true)
        setStatus(.applying)
        siteRouteStatusLabel.stringValue = "Refreshing"
        siteRouteStatusLabel.textColor = .secondaryLabelColor
        appendLog(ActivityMessage.repairing)

        Task.detached {
            do {
                _ = try RouteManager.repair(
                    input: input,
                    wifiInterface: interface,
                    publicDNS: publicDNS
                )
                let state = (try? RouteManager.siteRouteState(
                    for: target.value,
                    directInterface: interface
                )) ?? .unavailable

                await MainActor.run {
                    self.updateSiteRouteStatus(state, isListed: isListed)
                    self.appendLog(ActivityMessage.repaired)
                    self.setStatus(.verified)
                    self.setBusy(false)
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                    self.setBusy(false)
                }
            }
        }
    }

    @objc private func restoreNetwork() {
        setBusy(true)
        setStatus(.applying)
        appendLog(ActivityMessage.restoring)
        Task.detached {
            do {
                try AdaptiveController.restore()
                await MainActor.run {
                    self.appendLog(ActivityMessage.restoredSystem)
                    self.setStatus(.ready)
                    self.setBusy(false)
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                    self.setBusy(false)
                }
            }
        }
    }

    @objc private func removeHelper() {
        setBusy(true)
        setStatus(.applying)
        appendLog(ActivityMessage.removingHelper)
        Task.detached {
            do {
                try AdaptiveController.removeHelper()
                await MainActor.run {
                    self.appendLog(ActivityMessage.removedHelper)
                    self.setStatus(.ready)
                    self.setBusy(false)
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                    self.setBusy(false)
                }
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSponsorPage() {
        NSWorkspace.shared.open(ProductIdentity.sponsorURL)
    }

    private func recordSuccessfulApplyAndMaybePrompt() {
        var state = loadSponsorPromptState()
        SponsorPromptPolicy.recordSuccessfulApply(&state)
        saveSponsorPromptState(state)
        guard SponsorPromptPolicy.shouldPrompt(state) else { return }

        SponsorPromptPolicy.recordPromptShown(&state)
        saveSponsorPromptState(state)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "TunnelDetour helped?"
        alert.informativeText = "If TunnelDetour saves you time, you can support its continued development on GitHub."
        alert.addButton(withTitle: "Sponsor on GitHub")
        alert.addButton(withTitle: "Maybe Later")
        alert.addButton(withTitle: "Don’t Show Again")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            SponsorPromptPolicy.disable(&state)
            saveSponsorPromptState(state)
            NSWorkspace.shared.open(ProductIdentity.sponsorURL)
        case .alertThirdButtonReturn:
            SponsorPromptPolicy.disable(&state)
            saveSponsorPromptState(state)
        default:
            break
        }
    }

    private func loadSponsorPromptState() -> SponsorPromptState {
        guard let data = UserDefaults.standard.data(forKey: Self.sponsorPromptDefaultsKey),
              let state = try? JSONDecoder().decode(SponsorPromptState.self, from: data) else {
            return SponsorPromptState()
        }
        return state
    }

    private func saveSponsorPromptState(_ state: SponsorPromptState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.sponsorPromptDefaultsKey)
    }

    private func setBusy(_ busy: Bool) {
        if busy {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
        applyButton.isEnabled = !busy
        verifyButton.isEnabled = !busy
        saveButton.isEnabled = !busy
        resetButton.isEnabled = !busy
        checkSiteButton.isEnabled = !busy
        addSiteButton.isEnabled = !busy
        repairSiteButton.isEnabled = !busy
        settingsButton.isEnabled = !busy
        moreButton.isEnabled = true
        restoreMenuItem?.isEnabled = !busy
        removeHelperMenuItem?.isEnabled = !busy
        serviceSearchField.isEnabled = !busy
        serviceCheckboxes.values.forEach { $0.isEnabled = !busy }
        wifiField.isEnabled = !busy
        publicDNSField.isEnabled = !busy
        privateHostField.isEnabled = !busy
        googleServicesCheckbox.isEnabled = !busy
        adaptiveCheckbox.isEnabled = !busy
        siteSearchField.isEnabled = !busy
        domainsTextView.isEditable = !busy
        ipv4TextView.isEditable = !busy
    }

    private func updateSiteRouteStatus(_ state: SiteRouteState, isListed: Bool) {
        let listedText = isListed ? "Listed" : "Not listed"
        siteRouteStatusLabel.stringValue = "\(state.displayText) | \(listedText)"

        switch state {
        case .direct:
            siteRouteStatusLabel.textColor = .systemGreen
        case .mixed:
            siteRouteStatusLabel.textColor = .systemOrange
        case .privatePath:
            siteRouteStatusLabel.textColor = .systemRed
        case .unavailable:
            siteRouteStatusLabel.textColor = .secondaryLabelColor
        }
    }

    private func isTargetListed(_ target: RouteTarget) -> Bool {
        switch target.kind {
        case .domain:
            return activeDomainValues().contains { domain in
                target.value == domain || target.value.hasSuffix(".\(domain)")
            }
        case .ipv4:
            return parseLines(ipv4TextView.string)
                .map(RouteManager.normalizeHost)
                .contains(target.value)
        }
    }

    private func saveConfigFromControls() throws -> TunnelDetourConfig {
        let wifiInterface = wifiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let publicDNS = unique(parseTokens(publicDNSField.stringValue).filter(RouteManager.isIPv4))
        let domains = unique(parseLines(domainsTextView.string)
            .map(RouteManager.normalizeHost)
            .filter { !$0.isEmpty && !RouteManager.isIPv4($0) })
        guard domains.allSatisfy(NetworkInputValidator.isDomain) else {
            throw RouteManagerError.invalidTarget
        }
        let ipv4Targets = unique(parseLines(ipv4TextView.string)
            .map(RouteManager.normalizeHost)
            .filter(RouteManager.isIPv4))
        let privateHost = RouteManager.normalizeHost(privateHostField.stringValue)
        guard privateHost.isEmpty || NetworkInputValidator.isDomain(privateHost) else {
            throw RouteManagerError.invalidTarget
        }
        let enabledServiceIDs = Set(serviceCheckboxes.compactMap { id, checkbox in
            checkbox.state == .on ? id : nil
        })

        let next = TunnelDetourConfig(
            wifiInterface: wifiInterface.isEmpty ? TunnelDetourConfig.defaults.wifiInterface : wifiInterface,
            publicDNS: publicDNS.isEmpty ? TunnelDetourConfig.defaults.publicDNS : publicDNS,
            customDomainTargets: domains.map { RouteTarget(kind: .domain, value: $0) },
            enabledServiceIDs: enabledServiceIDs,
            ipv4Targets: ipv4Targets.map { RouteTarget(kind: .ipv4, value: $0) },
            privateCheckHost: privateHost,
            googleServicesDirect: googleServicesCheckbox.state == .on,
            adaptiveDirectSites: adaptiveCheckbox.state == .on
        )

        try store.save(next)
        config = next
        loadConfigIntoControls()
        return next
    }

    private func activeDomainValues() -> [String] {
        let customDomains = parseLines(domainsTextView.string).map(RouteManager.normalizeHost)
        let enabledServiceIDs = Set(serviceCheckboxes.compactMap { id, checkbox in
            checkbox.state == .on ? id : nil
        })
        let serviceDomains = TunnelDetourConfig.serviceGroups
            .filter { enabledServiceIDs.contains($0.id) }
            .flatMap(\.domains)
        return unique(customDomains + serviceDomains)
    }

    private func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }

        let timestamp = logFormatter.string(from: Date())
        let next = "[\(timestamp)] \(trimmed)"
        if logTextView.string.isEmpty {
            logTextView.string = next
        } else {
            logTextView.string += "\n\n\(next)"
        }
        logTextView.scrollToEndOfDocument(nil)
    }

    private func handleError(_ error: Error) {
        setStatus(.error)
        appendLog(ActivityMessage.failure(for: error))
    }

    private func parseLines(_ input: String) -> [String] {
        input
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseTokens(_ input: String) -> [String] {
        input
            .split { character in
                character.isWhitespace || character == "," || character == ";"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}

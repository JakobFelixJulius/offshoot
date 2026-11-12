import AppKit

/// A menu item that runs a closure, so menus can be built without selector plumbing.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, image: NSImage? = nil, key: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        self.image = image
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}

extension NSMenuItem {
    /// A disabled line of text; long text is shortened and shown in full as a tooltip.
    static func note(_ text: String, limit: Int = 90) -> NSMenuItem {
        let shortened = text.count > limit ? text.prefix(limit - 1) + "…" : Substring(text)
        let item = NSMenuItem(title: String(shortened), action: nil, keyEquivalent: "")
        item.isEnabled = false
        if shortened.count < text.count { item.toolTip = text }
        return item
    }
}

/// The Fetch All row. A custom view handles its own click, which is the only way a
/// menu item can act without closing the menu, so progress stays visible.
final class FetchAllView: NSView {
    var onClick: (@MainActor () -> Void)?

    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "Fetch All")
    private let shortcut = NSTextField(labelWithString: "⌘F")
    private var isFetching = false
    private var isEnabled = true
    private var isHovered = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        autoresizingMask = [.width]
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel("Fetch All")

        icon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        label.font = .menuFont(ofSize: 0)
        shortcut.font = .menuFont(ofSize: 0)

        for view in [icon, spinner, label, shortcut] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            spinner.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            shortcut.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcut.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(isFetching: Bool, isEnabled: Bool) {
        guard isFetching != self.isFetching || isEnabled != self.isEnabled else { return }
        self.isFetching = isFetching
        self.isEnabled = isEnabled
        label.stringValue = isFetching ? "Fetching…" : "Fetch All"
        icon.isHidden = isFetching
        if isFetching { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        setAccessibilityEnabled(isEnabled && !isFetching)
        needsDisplay = true
    }

    private var isHighlighted: Bool {
        isEnabled && !isFetching && (isHovered || enclosingMenuItem?.isHighlighted == true)
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        let active = isEnabled && !isFetching
        let text: NSColor =
            isHighlighted ? .selectedMenuItemTextColor : (active ? .labelColor : .disabledControlTextColor)
        label.textColor = text
        icon.contentTintColor = text
        shortcut.textColor = isHighlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, !isFetching else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isFetching else { return false }
        onClick?()
        return true
    }
}

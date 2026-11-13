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

/// A menu row that handles its own click. That is the only way a menu item can act
/// without closing the menu, so progress stays visible (Fetch All, Clean Up Worktrees).
final class KeepOpenMenuRow: NSView {
    var onClick: (@MainActor () -> Void)?

    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "")
    private var isBusy = false
    private var isEnabled = true
    private var isWarning = false
    private var isHovered = false

    init(title: String, symbol: String, shortcut shortcutText: String? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        autoresizingMask = [.width]
        setAccessibilityRole(.menuItem)

        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        shortcut.font = .menuFont(ofSize: 0)
        shortcut.stringValue = shortcutText ?? ""

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
        update(title: title, isBusy: false, isEnabled: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `isWarning` shows the row in red, used while it waits for a confirming second click.
    func update(title: String, isBusy: Bool, isEnabled: Bool, isWarning: Bool = false) {
        guard
            title != label.stringValue || isBusy != self.isBusy || isEnabled != self.isEnabled
                || isWarning != self.isWarning
        else { return }
        label.stringValue = title
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.isWarning = isWarning
        icon.isHidden = isBusy
        if isBusy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        setAccessibilityLabel(title)
        setAccessibilityEnabled(isEnabled && !isBusy)
        needsLayout = true
        needsDisplay = true
    }

    private var isActive: Bool { isEnabled && !isBusy }

    private var isHighlighted: Bool {
        isActive && (isHovered || enclosingMenuItem?.isHighlighted == true)
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        let normal: NSColor = isWarning ? .systemRed : .labelColor
        let text: NSColor = isHighlighted ? .selectedMenuItemTextColor : (isActive ? normal : .disabledControlTextColor)
        label.textColor = text
        icon.contentTintColor = text
        shortcut.textColor = isHighlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        (isWarning ? NSColor.systemRed : NSColor.selectedContentBackgroundColor).setFill()
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
        guard isActive else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isActive else { return false }
        onClick?()
        return true
    }
}

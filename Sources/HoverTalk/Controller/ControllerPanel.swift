import AppKit
import HoverTalkCore

/// The floating player controls: a borderless, non-activating panel that shows a
/// `ControllerPresentation` and reports button presses through `onAction`.
///
/// `.nonactivatingPanel` keeps the app being read frontmost when a button is clicked, and a
/// borderless window cannot become key (`NSWindow.canBecomeKey`), so the panel never takes
/// keyboard focus either.
@MainActor
final class ControllerPanel {
    private static let cornerRadius: CGFloat = 12

    var onAction: ((ControllerAction) -> Void)?

    private let panel = NSPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private let previousButton = ControlButton(symbolPointSize: 13)
    private let playPauseButton = ControlButton(symbolPointSize: 17)
    private let nextButton = ControlButton(symbolPointSize: 13)
    private let slowerButton = ControlButton(symbolPointSize: 12)
    private let fasterButton = ControlButton(symbolPointSize: 12)
    private let stopButton = ControlButton(symbolPointSize: 13)
    private let progressLabel = ControllerPanel.makeLabel(minimumWidth: 64, color: .secondaryLabelColor)
    private let rateLabel = ControllerPanel.makeLabel(minimumWidth: 44, color: .labelColor)

    init() {
        configurePanel()
        installContent()
    }

    func render(_ presentation: ControllerPresentation) {
        apply(presentation.previous, to: previousButton)
        apply(presentation.playPause, to: playPauseButton)
        apply(presentation.next, to: nextButton)
        apply(presentation.slower, to: slowerButton)
        apply(presentation.faster, to: fasterButton)
        apply(presentation.stop, to: stopButton)

        progressLabel.stringValue = presentation.progressText
        progressLabel.setAccessibilityLabel(presentation.progressAccessibilityLabel)
        rateLabel.stringValue = presentation.rateText
        rateLabel.setAccessibilityLabel(presentation.rateAccessibilityLabel)

        fitToContent()
        if presentation.isVisible {
            show()
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.title = ControllerPresentation.panelTitle
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // NSPanel hides on deactivation by default; keep it visible while another app is active.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
    }

    private func installContent() {
        for button in [previousButton, playPauseButton, nextButton, slowerButton, fasterButton, stopButton] {
            button.target = self
            button.action = #selector(buttonPressed(_:))
        }

        let stack = NSStackView(views: [
            previousButton, playPauseButton, nextButton,
            progressLabel,
            slowerButton, rateLabel, fasterButton,
            stopButton,
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.setCustomSpacing(10, after: nextButton)
        stack.setCustomSpacing(10, after: progressLabel)
        stack.setCustomSpacing(10, after: fasterButton)
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        // The panel is never key, so the material would otherwise draw in its inactive look.
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    // MARK: - Rendering

    private func apply(_ control: ControllerPresentation.Control, to button: ControlButton) {
        button.controllerAction = control.action
        button.setSymbol(control.symbolName, label: control.accessibilityLabel)
        button.isEnabled = control.isEnabled
    }

    /// Resizes the panel to its content, keeping its bottom edge and, to the nearest point
    /// below, its horizontal center.
    private func fitToContent() {
        guard let content = panel.contentView else { return }
        let size = content.fittingSize
        guard size != panel.frame.size else { return }
        var frame = panel.frame
        frame.origin.x += ((frame.width - size.width) / 2).rounded(.down)
        frame.size = size
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// Shows the panel at the bottom center of the screen under the mouse. A panel that is
    /// already visible is not moved back, so a position the user dragged it to is kept until
    /// the panel hides.
    private func show() {
        guard !panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            panel.setFrameOrigin(ControllerPlacement.origin(for: panel.frame.size, in: screen.visibleFrame))
        }
        // orderFrontRegardless brings the window forward even when its app is inactive (NSWindow
        // docs), which is the usual case for this accessory app.
        panel.orderFrontRegardless()
    }

    @objc private func buttonPressed(_ sender: ControlButton) {
        guard let action = sender.controllerAction else { return }
        onAction?(action)
    }

    // MARK: - Factories

    private static func makeLabel(minimumWidth: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = color
        label.alignment = .center
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth).isActive = true
        return label
    }

    /// A stretchable rounded rectangle; only its alpha matters to `maskImage`.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// An image-only button that remembers the `ControllerAction` it triggers.
private final class ControlButton: NSButton {
    var controllerAction: ControllerAction?

    init(symbolPointSize: CGFloat) {
        super.init(frame: .zero)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Click-through (`NSView.acceptsFirstMouse(for:)`): accepts the mouse-down that arrives
    /// while the window is not key, which is always the case for this panel, so a single click
    /// presses the button. Not yet checked on screen.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func setSymbol(_ name: String, label: String) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        toolTip = label
        setAccessibilityLabel(label)
    }
}

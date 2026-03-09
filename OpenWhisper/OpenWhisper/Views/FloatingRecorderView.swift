import SwiftUI
import AppKit

// MARK: - Pill Style (full indicator with optional preview)

struct FloatingRecorderPillView: View {
    @Environment(AppState.self) private var appState

    private let barCount = 12

    private var hasPreview: Bool {
        appState.settings.showLivePreview && !appState.livePreviewText.isEmpty
    }

    /// Show the last ~80 chars with "..." prefix if truncated
    static func previewSuffix(_ text: String, maxLength: Int = 80) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        // Find a word boundary near the cut point
        let suffix = String(trimmed.suffix(maxLength))
        if let spaceIdx = suffix.firstIndex(of: " ") {
            return "..." + suffix[suffix.index(after: spaceIdx)...]
        }
        return "..." + suffix
    }

    private var cornerRadius: CGFloat {
        hasPreview ? 20 : 100
    }

    var body: some View {
        VStack(spacing: 0) {
            // Waveform header
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.7), radius: 6)

                HStack(spacing: 3.5) {
                    ForEach(0..<barCount, id: \.self) { index in
                        WaveformBar(level: appState.audioLevel, index: index)
                    }
                }
                .frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Live preview text
            if appState.settings.showLivePreview && !appState.livePreviewText.isEmpty {
                Divider()
                    .opacity(0.3)

                Text(Self.previewSuffix(appState.livePreviewText))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 340, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: hasPreview)
    }
}

// MARK: - Minimal Style (compact dot)

struct FloatingRecorderMinimalView: View {
    @Environment(AppState.self) private var appState

    private var hasPreview: Bool {
        appState.settings.showLivePreview && !appState.livePreviewText.isEmpty
    }

    private var cornerRadius: CGFloat {
        hasPreview ? 18 : 100
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.7), radius: 6)

                HStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { index in
                        WaveformBar(level: appState.audioLevel, index: index)
                    }
                }
                .frame(height: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if hasPreview {
                Divider()
                    .opacity(0.3)

                Text(FloatingRecorderPillView.previewSuffix(appState.livePreviewText, maxLength: 60))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 280, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: hasPreview)
    }
}

// MARK: - Processing View

struct FloatingRecorderProcessingView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .foregroundStyle(.purple)
                .font(.system(size: 16))
                .symbolEffect(.pulse, isActive: animating)
            Text("Refining...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .onAppear { animating = true }
    }
}

// MARK: - Confirmation View

struct FloatingRecorderConfirmationView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16))
            Text("Done")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

// MARK: - Waveform Bar

struct WaveformBar: View {
    var level: Float
    var index: Int

    private var barHeight: CGFloat {
        let baseHeight: CGFloat = 4
        let maxExtra: CGFloat = 18
        let offsets: [Float] = [0.6, 1.0, 0.8, 0.95, 0.7, 0.85, 0.75, 0.9, 0.65, 1.0, 0.8, 0.7]
        let offset = offsets[index % offsets.count]
        let scaled = CGFloat(min(level * offset, 1.0))
        return baseHeight + maxExtra * scaled
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white.opacity(0.85))
            .frame(width: 3.5, height: barHeight)
            .animation(.easeOut(duration: 0.07), value: level)
    }
}

// MARK: - Demo Pill (for settings preview)

private struct DemoPillView: View {
    var level: Float

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.7), radius: 6)
            HStack(spacing: 3.5) {
                ForEach(0..<12, id: \.self) { index in
                    WaveformBar(level: level, index: index)
                }
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

private struct DemoMinimalView: View {
    var level: Float

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.7), radius: 6)
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { index in
                    WaveformBar(level: level, index: index)
                }
            }
            .frame(height: 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

// MARK: - Settings Preview

struct IndicatorPreview: View {
    var style: Constants.IndicatorStyle
    var isSelected: Bool

    @State private var demoLevel: Float = 0.5
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                switch style {
                case .pill:
                    DemoPillView(level: demoLevel)
                case .minimal:
                    DemoMinimalView(level: demoLevel)
                }
            }
            .scaleEffect(0.85)

            Text(style.label)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                demoLevel = Float.random(in: 0.2...0.9)
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

// MARK: - Wrapper view that positions content inside a fixed-size transparent canvas

/// Wraps a recording indicator view inside a large transparent frame.
/// The panel stays a fixed size; SwiftUI handles all layout and animation internally.
/// This eliminates NSHostingView background artifacts and AppKit frame animation jank.
private struct FloatingCanvasView<Content: View>: View {
    let content: Content
    let alignment: Alignment
    let canvasSize: CGSize

    /// Extra padding around content so shadows are not clipped by the window edge
    static var shadowMargin: CGFloat { 20 }

    var body: some View {
        ZStack {
            // Force SwiftUI to treat the entire canvas as transparent
            Color.clear

            content
                .padding(Self.shadowMargin)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: alignment)
    }
}

// MARK: - NSPanel Controller

@MainActor
final class FloatingRecorderController {
    private var panel: NSPanel?
    private weak var appState: AppState?

    /// Fixed canvas size for the panel — large enough for expanded content
    private static let canvasSize = CGSize(width: 500, height: 180)

    init(appState: AppState) {
        self.appState = appState
    }

    private var swiftUIAlignment: Alignment {
        guard let appState else { return .bottom }
        switch appState.settings.indicatorPosition {
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }

    func show() {
        guard panel == nil, let appState else { return }

        let style = appState.settings.indicatorStyle
        let alignment = swiftUIAlignment
        let canvas = Self.canvasSize

        let rootView: AnyView = switch style {
        case .pill:
            AnyView(
                FloatingCanvasView(
                    content: FloatingRecorderPillView().environment(appState),
                    alignment: alignment,
                    canvasSize: canvas
                )
            )
        case .minimal:
            AnyView(
                FloatingCanvasView(
                    content: FloatingRecorderMinimalView().environment(appState),
                    alignment: alignment,
                    canvasSize: canvas
                )
            )
        }

        let hosting = NSHostingView(rootView: rootView)
        hosting.setFrameSize(canvas)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: canvas),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        positionPanel(panel, size: canvas)

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    func showProcessing() {
        guard let panel, appState != nil else { return }

        let alignment = swiftUIAlignment
        let canvas = Self.canvasSize

        let processingView = FloatingCanvasView(
            content: FloatingRecorderProcessingView(),
            alignment: alignment,
            canvasSize: canvas
        )
        let hosting = NSHostingView(rootView: processingView)
        hosting.setFrameSize(canvas)
        panel.contentView = hosting
    }

    func showConfirmation() {
        guard let panel, appState != nil else { return }

        let alignment = swiftUIAlignment
        let canvas = Self.canvasSize

        let confirmView = FloatingCanvasView(
            content: FloatingRecorderConfirmationView(),
            alignment: alignment,
            canvasSize: canvas
        )
        let hosting = NSHostingView(rootView: confirmView)
        hosting.setFrameSize(canvas)
        panel.contentView = hosting

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.hide()
        }
    }

    private func positionPanel(_ panel: NSPanel, size: CGSize) {
        guard let screen = NSScreen.main, let appState else { return }
        let screenFrame = screen.visibleFrame
        let position = appState.settings.indicatorPosition
        // Visible margin from screen edge to content
        let margin: CGFloat = 16
        // The canvas has internal shadow padding, so offset the panel position to compensate
        let shadowPad = FloatingCanvasView<EmptyView>.shadowMargin

        let x: CGFloat
        let y: CGFloat

        switch position {
        case .topCenter:
            x = screenFrame.midX - size.width / 2
            y = screenFrame.maxY - size.height - margin + shadowPad
        case .bottomCenter:
            x = screenFrame.midX - size.width / 2
            y = screenFrame.minY + margin - shadowPad
        case .topLeft:
            x = screenFrame.minX + margin - shadowPad
            y = screenFrame.maxY - size.height - margin + shadowPad
        case .topRight:
            x = screenFrame.maxX - size.width - margin + shadowPad
            y = screenFrame.maxY - size.height - margin + shadowPad
        case .bottomLeft:
            x = screenFrame.minX + margin - shadowPad
            y = screenFrame.minY + margin - shadowPad
        case .bottomRight:
            x = screenFrame.maxX - size.width - margin + shadowPad
            y = screenFrame.minY + margin - shadowPad
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

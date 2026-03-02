import SwiftUI
import PDFKit
import AppKit

struct PDFUnlockContentView: View {
    @StateObject private var model: PDFUnlockModel
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    @AppStorage("backgroundTheme") private var backgroundThemeRaw: String = BackgroundTheme.frost.rawValue
    @State private var isSidebarDropTargeted = false

    init(model: PDFUnlockModel = PDFUnlockModel()) {
        _model = StateObject(wrappedValue: model)
    }

    private var localizer: Localizer {
        Localizer(language: AppLanguage(rawValue: appLanguageRaw) ?? .system)
    }

    private var backgroundTheme: BackgroundTheme {
        BackgroundTheme(rawValue: backgroundThemeRaw) ?? .frost
    }

    var body: some View {
        ZStack {
            UnlockGlassBackground(theme: backgroundTheme)
            HStack(spacing: 16) {
                UnlockSidebar(model: model, localizer: localizer, advancedOptionsEnabled: enableAdvancedOptions)
                    .frame(width: 380)
                    .dropDestination(
                        for: URL.self,
                        action: { items, _ in
                            model.handleDroppedFiles(items, allowBatch: enableAdvancedOptions)
                            return !items.isEmpty
                        },
                        isTargeted: { isSidebarDropTargeted = $0 }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                backgroundTheme.accentColor.opacity(isSidebarDropTargeted ? 0.95 : 0),
                                lineWidth: 2.2
                            )
                            .shadow(
                                color: backgroundTheme.accentColor.opacity(isSidebarDropTargeted ? 0.35 : 0),
                                radius: 8
                            )
                            .animation(.easeInOut(duration: 0.16), value: isSidebarDropTargeted)
                    )

                UnlockPreviewColumn(
                    title: localizer.t(.original),
                    subtitle: localizer.t(.beforeUnlock),
                    emptyText: localizer.t(.noPreview),
                    document: model.originalPreview,
                    scale: model.previewScale,
                    currentPageNumber: $model.currentPageNumber
                )

                UnlockPreviewColumn(
                    title: localizer.t(.afterUnlock),
                    subtitle: localizer.t(.expectedUnlocked),
                    emptyText: localizer.t(.noPreview),
                    document: model.unlockedPreview,
                    scale: model.previewScale,
                    currentPageNumber: $model.currentPageNumber
                )
            }
            .padding(18)
        }
        .frame(minWidth: 1220, minHeight: 740)
        .onChange(of: enableAdvancedOptions) { _, enabled in
            if !enabled {
                model.processingMode = .single
            }
        }
    }
}

private struct UnlockSidebar: View {
    @ObservedObject var model: PDFUnlockModel
    let localizer: Localizer
    let advancedOptionsEnabled: Bool

    private let appIcon: NSImage = {
        let icon = NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.isTemplate = false
        return icon
    }()

    private let pageFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        return formatter
    }()

    private let actionColumns = [
        GridItem(.flexible(), spacing: 8, alignment: .leading),
        GridItem(.flexible(), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        UnlockGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(localizer.t(.toolUnlock))
                        .font(.title3)
                        .bold()
                }
                .padding(.top, 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        UnlockSidebarSection(title: localizer.t(.files)) {
                            VStack(alignment: .leading, spacing: 18) {
                                if advancedOptionsEnabled {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(localizer.t(.mode))
                                            .font(.subheadline)
                                            .bold()
                                        Picker("", selection: $model.processingMode) {
                                            Text(localizer.t(.single)).tag(ProcessingMode.single)
                                            Text(localizer.t(.batch)).tag(ProcessingMode.batch)
                                        }
                                        .pickerStyle(.segmented)
                                        .labelsHidden()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }

                                if advancedOptionsEnabled && model.isBatchMode {
                                    HStack {
                                        Text(localizer.t(.input))
                                            .font(.subheadline)
                                            .bold()
                                        Spacer()
                                        Button(localizer.t(.selectPDFs)) { model.pickBatchInputs() }
                                            .disabled(model.isRunning)
                                        Button(localizer.t(.clear)) { model.clearSelection() }
                                            .disabled(model.batchInputURLs.isEmpty || model.isRunning)
                                    }
                                    Text(localizer.format(.filesSelected, model.batchInputURLs.count))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 6) {
                                            ForEach(Array(model.batchInputURLs.enumerated()), id: \.element) { index, url in
                                                UnlockBatchFileRow(
                                                    index: index,
                                                    url: url,
                                                    currentIndex: model.batchIndex,
                                                    isRunning: model.isRunning,
                                                    removeTooltip: localizer.t(.removeFromBatchList),
                                                    onSelect: { model.switchToBatchIndex(index) },
                                                    onRemove: { model.removeBatchInput(at: index) }
                                                )
                                            }

                                            if model.batchInputURLs.isEmpty {
                                                Text(localizer.t(.noFileSelected))
                                                    .foregroundStyle(.secondary)
                                                    .font(.caption)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .background(UnlockScrollViewStyleConfigurator())
                                    .frame(maxHeight: 140)

                                    Divider()

                                    HStack {
                                        Text(localizer.t(.output))
                                            .font(.subheadline)
                                            .bold()
                                        Spacer()
                                        Button(localizer.t(.selectOutput)) { model.pickBatchOutputDirectory() }
                                            .disabled(model.batchInputURLs.isEmpty || model.isRunning)
                                        Button(localizer.t(.auto)) { model.batchOutputDirectory = nil }
                                            .disabled(model.batchOutputDirectory == nil)
                                    }
                                    Text(model.batchOutputDirectory?.lastPathComponent ?? localizer.t(.sameAsInputFolder))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack {
                                        Text(localizer.t(.input))
                                            .font(.subheadline)
                                            .bold()
                                        Spacer()
                                        Button(localizer.t(.selectPDF)) { model.pickInput() }
                                            .disabled(model.isRunning)
                                        Button(localizer.t(.clear)) { model.clearSelection() }
                                            .disabled(model.inputURL == nil || model.isRunning)
                                    }
                                    Text(model.inputURL?.lastPathComponent ?? localizer.t(.noFileSelected))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Divider()

                                    HStack {
                                        Text(localizer.t(.output))
                                            .font(.subheadline)
                                            .bold()
                                        Spacer()
                                        Button(localizer.t(.selectOutput)) { model.pickOutput() }
                                            .disabled(model.inputURL == nil || model.isRunning)
                                    }
                                    let name = model.outputURL?.lastPathComponent
                                        ?? model.suggestedOutputURL?.lastPathComponent
                                        ?? localizer.t(.auto)
                                    Text(name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        UnlockSidebarSection(title: localizer.t(.unlockPassword)) {
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField(localizer.t(.passwordPlaceholder), text: $model.unlockPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(model.isRunning)

                                Text(model.isCurrentFileLocked ? localizer.t(.locked) : localizer.t(.unlocked))
                                    .font(.caption)
                                    .foregroundStyle(model.isCurrentFileLocked ? .orange : .secondary)

                                if advancedOptionsEnabled && model.isBatchMode && model.hasLockedInputsInBatch {
                                    Text(localizer.t(.batchPasswordHint))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let message = model.passwordErrorMessage {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }

                        UnlockSidebarSection(title: localizer.t(.action)) {
                            VStack(alignment: .leading, spacing: 10) {
                                let isBatch = advancedOptionsEnabled && model.isBatchMode
                                Button(model.isRunning ? localizer.t(.processing) : (isBatch ? localizer.t(.startBatch) : localizer.t(.start))) {
                                    model.start()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.canProcess || model.isRunning)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                LazyVGrid(columns: actionColumns, spacing: 8) {
                                    Button(localizer.t(.save)) {
                                        model.saveAs()
                                    }
                                    .disabled(!model.canProcess || model.isRunning || isBatch)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Button(localizer.t(.replace)) {
                                        model.replaceOriginal()
                                    }
                                    .disabled(!model.canReplaceOriginal || model.isRunning)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Button(localizer.t(.deleteOriginal)) {
                                        model.deleteOriginal()
                                    }
                                    .disabled(model.inputURL == nil || model.isRunning)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if model.isRunning {
                                    ProgressView(value: model.progress)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }

                        if advancedOptionsEnabled && model.isBatchMode {
                            UnlockSidebarSection(title: localizer.t(.previewFile)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    let total = model.batchInputURLs.count
                                    let current = total == 0 ? 0 : (model.batchIndex + 1)
                                    let name = model.inputURL?.lastPathComponent ?? localizer.t(.noFileSelected)
                                    HStack(spacing: 8) {
                                        Button {
                                            model.stepBatchItem(-1)
                                        } label: {
                                            Image(systemName: "chevron.left")
                                        }
                                        .frame(width: 28, height: 28)
                                        .disabled(model.batchIndex <= 0)

                                        Text("\(current)/\(total) \(name)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .center)

                                        Button {
                                            model.stepBatchItem(1)
                                        } label: {
                                            Image(systemName: "chevron.right")
                                        }
                                        .frame(width: 28, height: 28)
                                        .disabled(model.batchIndex >= model.batchInputURLs.count - 1)
                                    }
                                }
                            }
                        }

                        UnlockSidebarSection(title: localizer.t(.navigation)) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Button {
                                        model.stepPage(-1)
                                    } label: {
                                        Image(systemName: "chevron.left")
                                    }
                                    .disabled(model.currentPageNumber <= 1)

                                    TextField(localizer.t(.page), value: pageBinding, formatter: pageFormatter)
                                        .frame(width: 60)
                                        .multilineTextAlignment(.center)
                                        .textFieldStyle(.roundedBorder)

                                    Text("/ \(model.pageCount)")
                                        .foregroundStyle(.secondary)

                                    Button {
                                        model.stepPage(1)
                                    } label: {
                                        Image(systemName: "chevron.right")
                                    }
                                    .disabled(model.pageCount == 0 || model.currentPageNumber >= model.pageCount)

                                    Spacer()
                                }
                            }
                        }

                        UnlockSidebarSection(title: localizer.t(.zoom), showsDivider: false) {
                            HStack(spacing: 8) {
                                Button {
                                    model.zoomOut()
                                } label: {
                                    Image(systemName: "minus")
                                }
                                .disabled(model.originalPreview == nil)

                                Text("\(Int(model.previewScale * 100))%")
                                    .frame(width: 52, alignment: .center)
                                    .foregroundStyle(.secondary)

                                Button {
                                    model.zoomIn()
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .disabled(model.originalPreview == nil)

                                Button(localizer.t(.reset)) {
                                    model.resetZoom()
                                }
                                .disabled(model.originalPreview == nil)

                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.trailing, 10)
                }
                .background(UnlockScrollViewStyleConfigurator())
            }
        }
    }

    private var pageBinding: Binding<Int> {
        Binding(
            get: { model.currentPageNumber },
            set: { model.setCurrentPageNumber($0) }
        )
    }
}

private struct UnlockBatchFileRow: View {
    let index: Int
    let url: URL
    let currentIndex: Int
    let isRunning: Bool
    let removeTooltip: String
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    if index == currentIndex {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(index == currentIndex ? Color.white.opacity(0.6) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .help(removeTooltip)
        }
    }
}

private struct UnlockSidebarSection<Content: View>: View {
    let title: String
    let showsDivider: Bool
    let content: Content

    init(title: String, showsDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
            if showsDivider {
                UnlockDashedDivider()
                    .padding(.top, 6)
            }
        }
    }
}

private struct UnlockDashedDivider: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
            }
            .stroke(
                Color.black.opacity(0.24),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [4, 6])
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 1)
    }
}

private struct UnlockScrollViewStyleConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var view: NSView? = nsView
            var scrollView: NSScrollView?
            while let current = view, scrollView == nil {
                scrollView = current as? NSScrollView
                view = current.superview
            }
            guard let scrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.alphaValue = 0.25
            scrollView.horizontalScroller?.alphaValue = 0.25
        }
    }
}

private struct UnlockPreviewColumn: View {
    let title: String
    let subtitle: String
    let emptyText: String
    let document: PDFDocument?
    let scale: CGFloat
    @Binding var currentPageNumber: Int

    var body: some View {
        UnlockGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ZStack {
                    if document != nil {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
                            .background(Color.clear)
                    }

                    if let document {
                        PDFKitView(
                            document: document,
                            scale: scale,
                            currentPageNumber: $currentPageNumber,
                            onPageChanged: nil
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(6)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "doc")
                            Text(emptyText)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct UnlockGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

private struct UnlockGlassBackground: View {
    let theme: BackgroundTheme

    var body: some View {
        LinearGradient(
            colors: [
                theme.topColor,
                theme.bottomColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .blur(radius: 90)
                    .offset(x: -220, y: -180)
                Circle()
                    .fill(theme.accentColor.opacity(0.25))
                    .blur(radius: 130)
                    .offset(x: 260, y: 220)
                RoundedRectangle(cornerRadius: 120)
                    .fill(Color.white.opacity(0.12))
                    .blur(radius: 60)
                    .rotationEffect(.degrees(12))
                    .offset(x: -140, y: 200)
            }
        )
    }
}

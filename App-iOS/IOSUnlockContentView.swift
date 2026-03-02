import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct IOSUnlockContentView: View {
    @StateObject private var model = IOSUnlockModel()
    @State private var showFileImporter = false
    @State private var activeImporter: ActiveImporter = .pdf
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showFileSection = true
    @State private var showPasswordSection = true
    @State private var showActionSection = true
    @State private var showNavigationSection = true
    @State private var showSingleSaveExporter = false
    @State private var singleSaveDocument = IOSUnlockPDFExportDocument(data: Data())
    @State private var singleSaveFilename = "unlocked.pdf"
    @State private var pendingCriticalAction: CriticalAction?
    @State private var detailMode: DetailMode = .comparison
    @State private var phoneTab: PhoneTab = .home

    @AppStorage("appLanguage") private var appLanguageRaw: String = IOSAppLanguage.system.rawValue
    @AppStorage("backgroundTheme") private var backgroundThemeRaw: String = IOSBackgroundTheme.frost.rawValue
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    @AppStorage("iosToolPage") private var selectedToolRaw: String = IOSToolPage.unlock.rawValue

    enum ActiveImporter {
        case pdf
        case folder
    }

    enum CriticalAction: String, Identifiable {
        case replaceSingle
        case replaceBatch
        case deleteSingle
        case deleteBatch

        var id: String { rawValue }
    }

    enum DetailMode: String, CaseIterable, Identifiable {
        case comparison
        case original
        case unlocked

        var id: String { rawValue }
    }

    enum PhoneTab: Hashable {
        case home
        case preview
    }

    private var appLanguage: IOSAppLanguage {
        IOSAppLanguage(rawValue: appLanguageRaw) ?? .system
    }

    private var backgroundTheme: IOSBackgroundTheme {
        IOSBackgroundTheme(rawValue: backgroundThemeRaw) ?? .frost
    }

    private var localizer: IOSLocalizer {
        IOSLocalizer(language: appLanguage)
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var selectedToolBinding: Binding<IOSToolPage> {
        Binding(
            get: { IOSToolPage(rawValue: selectedToolRaw) ?? .unlock },
            set: { selectedToolRaw = $0.rawValue }
        )
    }

    private var importerContentTypes: [UTType] {
        switch activeImporter {
        case .pdf:
            return [.pdf]
        case .folder:
            return [.folder]
        }
    }

    private var importerAllowsMultipleSelection: Bool {
        switch activeImporter {
        case .pdf:
            return enableAdvancedOptions
        case .folder:
            return false
        }
    }

    private var startButtonTitle: String {
        if model.isRunning {
            return localizer.t(.processing)
        }
        return model.isBatchMode ? localizer.t(.startBatch) : localizer.t(.start)
    }

    private var fileButtonTitle: String {
        if enableAdvancedOptions && model.isBatchMode {
            return localizer.t(.choosePDFs)
        }
        return localizer.t(.choosePDF)
    }

    var body: some View {
        ZStack {
            IOSGlassBackground(theme: backgroundTheme)
            if isPad {
                ipadLayout
            } else {
                phoneLayout
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importerContentTypes,
            allowsMultipleSelection: importerAllowsMultipleSelection
        ) { result in
            switch activeImporter {
            case .pdf:
                switch result {
                case .success(let urls):
                    importPickedFiles(urls)
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                    model.status = localizer.format(.pickFileFailed, error.localizedDescription)
                }
            case .folder:
                switch result {
                case .success(let urls):
                    guard let folder = urls.first else { return }
                    model.saveBatchOutputs(to: folder)
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                    model.status = localizer.format(.pickFolderFailed, error.localizedDescription)
                }
            }
        }
        .dropDestination(for: URL.self) { items, _ in
            model.handlePickedFiles(items, allowBatch: enableAdvancedOptions)
            return !items.isEmpty
        }
        .fileExporter(
            isPresented: $showSingleSaveExporter,
            document: singleSaveDocument,
            contentType: .pdf,
            defaultFilename: singleSaveFilename
        ) { result in
            switch result {
            case .success(let savedURL):
                model.markSingleSaveAsCompleted(destination: savedURL)
            case .failure(let error):
                model.errorMessage = error.localizedDescription
                model.status = localizer.format(.saveFailed, error.localizedDescription)
            }
        }
        .confirmationDialog(
            confirmationTitle(for: pendingCriticalAction),
            isPresented: Binding(
                get: { pendingCriticalAction != nil },
                set: { presented in
                    if !presented { pendingCriticalAction = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingCriticalAction
        ) { action in
            Button(localizer.t(.confirmAction), role: .destructive) {
                performCriticalAction(action)
            }
            Button(localizer.t(.cancel), role: .cancel) {
                pendingCriticalAction = nil
            }
        } message: { action in
            Text(confirmationMessage(for: action))
        }
        .alert(localizer.t(.processFailed), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { presented in
                if !presented {
                    model.errorMessage = nil
                }
            }
        )) {
            Button(localizer.t(.ok), role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onChange(of: enableAdvancedOptions) { _, enabled in
            if !enabled {
                model.processingMode = .single
            }
        }
    }

    private var ipadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            detail
                .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(backgroundTheme.accentColor)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var phoneLayout: some View {
        TabView(selection: $phoneTab) {
            phoneHomeTab
                .tag(PhoneTab.home)
                .tabItem {
                    Label(localizer.t(.files), systemImage: "doc")
                }

            phonePreviewTab
                .tag(PhoneTab.preview)
                .tabItem {
                    Label(localizer.t(.preview), systemImage: "doc.text.image")
                }
        }
        .tint(backgroundTheme.accentColor)
    }

    private var phoneHomeTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    phonePrimaryActions
                    phoneModeSection
                    filesSection
                    passwordSection
                    actionSection
                    navigationSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(localizer.t(.toolUnlock))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var phonePrimaryActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(fileButtonTitle) {
                    presentPDFPicker()
                }
                .buttonStyle(.borderedProminent)

                Button(startButtonTitle) {
                    model.process()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canProcess)
            }

            HStack(spacing: 8) {
                Label(model.inputURL?.lastPathComponent ?? localizer.t(.selectFileHint), systemImage: "doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    model.clearInputs()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.isRunning || (model.inputURL == nil && model.batchInputURLs.isEmpty))
            }
        }
        .modifier(IOSUnlockSidebarCardStyle())
    }

    @ViewBuilder
    private var phoneModeSection: some View {
        if enableAdvancedOptions {
            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.t(.mode))
                    .font(.subheadline.weight(.semibold))

                Picker(localizer.t(.mode), selection: $model.processingMode) {
                    Text(localizer.t(.single)).tag(IOSUnlockProcessingMode.single)
                    Text(localizer.t(.batch)).tag(IOSUnlockProcessingMode.batch)
                }
                .pickerStyle(.segmented)
            }
            .modifier(IOSUnlockSidebarCardStyle())
        }
    }

    private var phonePreviewTab: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Picker(localizer.t(.preview), selection: $detailMode) {
                    Text(localizer.t(.comparison)).tag(DetailMode.comparison)
                    Text(localizer.t(.original)).tag(DetailMode.original)
                    Text(localizer.t(.unlockAfter)).tag(DetailMode.unlocked)
                }
                .pickerStyle(.segmented)

                switch detailMode {
                case .comparison:
                    VStack(spacing: 10) {
                        previewCard(title: localizer.t(.original), document: model.originalPreview)
                        previewCard(title: localizer.t(.unlockAfter), document: model.unlockedPreview)
                    }
                case .original:
                    previewCard(title: localizer.t(.original), document: model.originalPreview)
                case .unlocked:
                    previewCard(title: localizer.t(.unlockAfter), document: model.unlockedPreview)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(localizer.t(.preview))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            fixedTopPanel
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    modeSection
                    filesSection
                    passwordSection
                    actionSection
                    navigationSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fixedTopPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isPad {
                Picker("", selection: selectedToolBinding) {
                    Text(localizer.t(.toolMarkClean)).tag(IOSToolPage.markClean)
                    Text(localizer.t(.toolUnlock)).tag(IOSToolPage.unlock)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: 10) {
                Image(systemName: "lock.open.display")
                    .font(.title3)
                    .foregroundStyle(backgroundTheme.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t(.toolUnlock))
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.inputURL?.lastPathComponent ?? localizer.t(.selectFileHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button(fileButtonTitle) {
                    presentPDFPicker()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button(startButtonTitle) {
                    model.process()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canProcess)
                .frame(maxWidth: .infinity)

                Button(role: .destructive) {
                    model.clearInputs()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning || (model.inputURL == nil && model.batchInputURLs.isEmpty))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
        )
        .padding(12)
    }

    @ViewBuilder
    private var modeSection: some View {
        if enableAdvancedOptions {
            DisclosureGroup(isExpanded: .constant(true)) {
                Picker(localizer.t(.mode), selection: $model.processingMode) {
                    Text(localizer.t(.single)).tag(IOSUnlockProcessingMode.single)
                    Text(localizer.t(.batch)).tag(IOSUnlockProcessingMode.batch)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)
            } label: {
                sectionHeader(title: localizer.t(.mode), icon: "switch.2")
            }
            .modifier(IOSUnlockSidebarCardStyle())
        }
    }

    private var filesSection: some View {
        DisclosureGroup(isExpanded: $showFileSection) {
            VStack(alignment: .leading, spacing: 8) {
                if enableAdvancedOptions && model.isBatchMode {
                    Text(localizer.format(.filesCount, model.batchInputURLs.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.batchInputURLs.isEmpty {
                        Text(localizer.t(.batchEmpty))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.batchInputURLs.indices), id: \.self) { index in
                            unlockBatchRow(url: model.batchInputURLs[index], index: index)
                        }
                    }
                } else {
                    Text(model.inputURL?.lastPathComponent ?? localizer.t(.noFileSelected))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.files), icon: "folder")
        }
        .modifier(IOSUnlockSidebarCardStyle())
    }

    private var passwordSection: some View {
        DisclosureGroup(isExpanded: $showPasswordSection) {
            VStack(alignment: .leading, spacing: 10) {
                SecureField(localizer.t(.passwordPlaceholder), text: $model.unlockPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.isRunning)

                Text(model.isCurrentFileLocked ? localizer.t(.locked) : localizer.t(.unlocked))
                    .font(.caption)
                    .foregroundStyle(model.isCurrentFileLocked ? .orange : .secondary)

                if enableAdvancedOptions && model.isBatchMode && model.hasLockedInputsInBatch {
                    Text(localizer.t(.batchPasswordHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let passwordError = model.passwordErrorMessage {
                    Text(passwordError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.unlockPassword), icon: "key")
        }
        .modifier(IOSUnlockSidebarCardStyle())
    }

    private var actionSection: some View {
        DisclosureGroup(isExpanded: $showActionSection) {
            VStack(alignment: .leading, spacing: 8) {
                if model.isBatchMode {
                    HStack(spacing: 8) {
                        Button(localizer.t(.saveBatch)) {
                            presentFolderPicker()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canSaveAsBatch)

                        Button(localizer.t(.replaceBatch), role: .destructive) {
                            pendingCriticalAction = .replaceBatch
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canReplaceOriginal)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button(localizer.t(.deleteBatch), role: .destructive) {
                            pendingCriticalAction = .deleteBatch
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canDeleteOriginal)

                        Spacer(minLength: 0)
                    }

                    if model.batchOutputURLs.isEmpty {
                        Text(localizer.t(.exportHintBatch))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.batchOutputURLs, id: \.path) { output in
                            HStack {
                                Text(output.lastPathComponent)
                                    .font(.footnote)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                ShareLink(item: output) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                } else if let output = model.outputURL {
                    HStack(spacing: 8) {
                        Button(localizer.t(.saveAs)) {
                            prepareSingleSaveAs()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canSaveAsSingle)

                        Button(localizer.t(.replaceOriginal), role: .destructive) {
                            pendingCriticalAction = .replaceSingle
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canReplaceOriginal)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button(localizer.t(.deleteOriginal), role: .destructive) {
                            pendingCriticalAction = .deleteSingle
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canDeleteOriginal)

                        Spacer(minLength: 0)
                    }

                    Text(output.lastPathComponent)
                        .font(.footnote)
                        .lineLimit(2)

                    ShareLink(item: output) {
                        Label(localizer.t(.export), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 8) {
                        Button(localizer.t(.saveAs)) {}
                            .buttonStyle(.borderedProminent)
                            .disabled(true)

                        Button(localizer.t(.replaceOriginal), role: .destructive) {
                            pendingCriticalAction = .replaceSingle
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canReplaceOriginal)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button(localizer.t(.deleteOriginal), role: .destructive) {
                            pendingCriticalAction = .deleteSingle
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canDeleteOriginal)

                        Spacer(minLength: 0)
                    }

                    Text(localizer.t(.exportHintSingle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if model.isRunning {
                    ProgressView(value: model.progress)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.export), icon: "square.and.arrow.up")
        }
        .modifier(IOSUnlockSidebarCardStyle())
    }

    private var navigationSection: some View {
        DisclosureGroup(isExpanded: $showNavigationSection) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        model.stepPage(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.currentPageNumber <= 1)

                    Text("\(model.currentPageNumber)")
                        .font(.footnote.monospacedDigit())
                        .frame(width: 42, alignment: .center)

                    Text("/ \(model.pageCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        model.stepPage(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.pageCount == 0 || model.currentPageNumber >= model.pageCount)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        model.zoomOut()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.originalPreview == nil)

                    Text("\(Int(model.previewScale * 100))%")
                        .font(.footnote.monospacedDigit())
                        .frame(width: 52, alignment: .center)

                    Button {
                        model.zoomIn()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.originalPreview == nil)

                    Button(localizer.t(.reset)) {
                        model.resetZoom()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.originalPreview == nil)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.navigation), icon: "arrow.left.and.right")
        }
        .modifier(IOSUnlockSidebarCardStyle())
    }

    private var detail: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t(.toolUnlock))
                        .font(.title3.bold())
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if model.isBatchMode {
                    batchNavigator
                }

                switch detailMode {
                case .comparison:
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            previewCard(title: localizer.t(.unlockBefore), document: model.originalPreview)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            previewCard(title: localizer.t(.unlockAfter), document: model.unlockedPreview)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        VStack(spacing: 12) {
                            previewCard(title: localizer.t(.unlockBefore), document: model.originalPreview)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            previewCard(title: localizer.t(.unlockAfter), document: model.unlockedPreview)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .original:
                    previewCard(title: localizer.t(.unlockBefore), document: model.originalPreview)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unlocked:
                    previewCard(title: localizer.t(.unlockAfter), document: model.unlockedPreview)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .top, spacing: 6) {
            HStack {
                Spacer()
                unlockTabBar
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    private var unlockTabBar: some View {
        HStack(spacing: 4) {
            Button(action: toggleSidebar) {
                Image(systemName: columnVisibility == .detailOnly ? "sidebar.leading" : "sidebar.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 32)
                    .padding(.horizontal, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.74))
                    )
            }
            .buttonStyle(.plain)

            ForEach(DetailMode.allCases) { mode in
                let selected = detailMode == mode
                Button {
                    detailMode = mode
                } label: {
                    Text(detailTitle(for: mode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selected ? Color.white.opacity(0.88) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.40), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
        .frame(maxWidth: 460, alignment: .center)
    }

    private var batchNavigator: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.batchInputURLs.isEmpty {
                Text(localizer.t(.batchEmpty))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Button {
                        model.stepBatchItem(-1)
                    } label: {
                        Label(localizer.t(.previous), systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.batchIndex <= 0)

                    Button {
                        model.stepBatchItem(1)
                    } label: {
                        Label(localizer.t(.next), systemImage: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.batchIndex >= model.batchInputURLs.count - 1)

                    Spacer()

                    Text("\(model.batchIndex + 1)/\(model.batchInputURLs.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let inputURL = model.inputURL {
                    Text(inputURL.lastPathComponent)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func unlockBatchRow(url: URL, index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                model.switchToBatchIndex(index)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: index == model.batchIndex ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(index == model.batchIndex ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.footnote)
                            .lineLimit(1)
                        Text(localizer.format(.itemIndex, index + 1))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if !model.isRunning {
                Button(role: .destructive) {
                    model.removeBatchInput(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func previewCard(title: String, document: PDFDocument?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if let document {
                IOSUnlockPDFKitView(
                    document: document,
                    currentPageNumber: $model.currentPageNumber,
                    scale: model.previewScale
                )
                .id(ObjectIdentifier(document))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.secondary.opacity(0.12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        Text(localizer.t(.noPreview))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    @ViewBuilder
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(backgroundTheme.accentColor)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func detailTitle(for mode: DetailMode) -> String {
        switch mode {
        case .comparison:
            return localizer.t(.comparison)
        case .original:
            return localizer.t(.original)
        case .unlocked:
            return localizer.t(.unlockAfter)
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    private func presentPDFPicker() {
        activeImporter = .pdf
        showFileImporter = true
    }

    private func presentFolderPicker() {
        activeImporter = .folder
        showFileImporter = true
    }

    private func importPickedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        model.handlePickedFiles(urls, allowBatch: enableAdvancedOptions)
    }

    private func prepareSingleSaveAs() {
        guard let payload = model.prepareSingleExportPayload() else { return }
        singleSaveDocument = IOSUnlockPDFExportDocument(data: payload.data)
        singleSaveFilename = payload.filename
        showSingleSaveExporter = true
    }

    private func performCriticalAction(_ action: CriticalAction) {
        pendingCriticalAction = nil
        switch action {
        case .replaceSingle, .replaceBatch:
            model.replaceOriginals()
        case .deleteSingle, .deleteBatch:
            model.deleteOriginals()
        }
    }

    private func confirmationTitle(for action: CriticalAction?) -> String {
        guard let action else { return "" }
        switch action {
        case .replaceSingle:
            return localizer.t(.confirmReplaceSingleTitle)
        case .replaceBatch:
            return localizer.t(.confirmReplaceBatchTitle)
        case .deleteSingle:
            return localizer.t(.confirmDeleteSingleTitle)
        case .deleteBatch:
            return localizer.t(.confirmDeleteBatchTitle)
        }
    }

    private func confirmationMessage(for action: CriticalAction) -> String {
        switch action {
        case .replaceSingle:
            return localizer.t(.confirmReplaceSingleMessage)
        case .replaceBatch:
            let ready = model.batchReplaceReadyCount
            let total = model.batchDocumentCount
            let skipped = max(0, total - ready)
            if skipped > 0 {
                return localizer.format(.confirmReplaceBatchMessageWithSkipped, ready, skipped)
            }
            return localizer.format(.confirmReplaceBatchMessage, ready)
        case .deleteSingle:
            return localizer.t(.confirmDeleteSingleMessage)
        case .deleteBatch:
            return localizer.format(.confirmDeleteBatchMessage, model.batchDocumentCount)
        }
    }
}

private struct IOSUnlockPDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let content = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = content
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct IOSUnlockSidebarCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.28))
            )
    }
}

private struct IOSUnlockPDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageNumber: Int
    let scale: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPageNumber: $currentPageNumber)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .systemBackground
        view.document = document
        context.coordinator.bind(to: view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = document
        }

        if let page = uiView.document?.page(at: max(0, currentPageNumber - 1)),
           uiView.currentPage !== page {
            uiView.go(to: page)
        }

        let fit = uiView.scaleFactorForSizeToFit
        if fit > 0 {
            uiView.autoScales = false
            uiView.minScaleFactor = fit * 0.6
            uiView.maxScaleFactor = max(fit * 6, 4)
            uiView.scaleFactor = min(max(fit * scale, uiView.minScaleFactor), uiView.maxScaleFactor)
        } else {
            uiView.autoScales = true
        }
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    final class Coordinator {
        private let currentPageNumber: Binding<Int>
        private weak var pdfView: PDFView?
        private var pageChangedObserver: NSObjectProtocol?

        init(currentPageNumber: Binding<Int>) {
            self.currentPageNumber = currentPageNumber
        }

        func bind(to view: PDFView) {
            unbind()
            pdfView = view
            pageChangedObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                guard let self, let view = self.pdfView else { return }
                guard let page = view.currentPage,
                      let document = view.document else { return }
                let index = document.index(for: page)
                guard index >= 0 else { return }
                let number = index + 1
                if self.currentPageNumber.wrappedValue != number {
                    self.currentPageNumber.wrappedValue = number
                }
            }
        }

        func unbind() {
            if let observer = pageChangedObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            pageChangedObserver = nil
            pdfView = nil
        }
    }
}

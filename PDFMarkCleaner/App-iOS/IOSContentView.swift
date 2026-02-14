import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import UIKit
import PDFMarkCore

struct IOSContentView: View {
    @StateObject private var model = IOSAppModel()
    @State private var showFileImporter = false
    @State private var activeImporter: ActiveImporter = .pdf
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var detailMode: DetailMode = .comparison

    @State private var showSettingsSection = true
    @State private var showFilesSection = true
    @State private var showPageRangeSection = true
    @State private var showTypeSection = true
    @State private var showExportSection = true
    @State private var showAllAnnotationTypes = false
    @State private var showSingleSaveExporter = false
    @State private var singleSaveDocument = PDFExportDocument(data: Data())
    @State private var singleSaveFilename = "cleaned.pdf"
    @State private var showMarkReportExporter = false
    @State private var markReportDocument = TextExportDocument(data: Data())
    @State private var markReportFilename = "marked_report.txt"
    @State private var pendingCriticalAction: CriticalExportAction?
    @State private var phoneTab: PhoneTab = .home

    @AppStorage("appLanguage") private var appLanguageRaw: String = IOSAppLanguage.system.rawValue
    @AppStorage("backgroundTheme") private var backgroundThemeRaw: String = IOSBackgroundTheme.frost.rawValue
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    @AppStorage("preferBatchMode") private var preferBatchMode = false

    private let typeColumns = [
        GridItem(.adaptive(minimum: 120), spacing: 8)
    ]

    enum DetailMode: String, CaseIterable, Identifiable {
        case comparison
        case original
        case cleaned

        var id: String { rawValue }
    }

    enum ActiveImporter {
        case pdf
        case folder
    }

    enum PhoneTab: Hashable {
        case home
        case preview
        case settings
    }

    enum CriticalExportAction: String, Identifiable {
        case replaceSingle
        case replaceBatch
        case deleteSingle
        case deleteBatch

        var id: String { rawValue }
    }

    enum ActiveAlert {
        case processError(String)
        case noMarks(String)
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

    private var visibleAnnotationKinds: [AnnotationKind] {
        let all = AnnotationKind.allCases
        if showAllAnnotationTypes || all.count <= 10 {
            return all
        }
        return Array(all.prefix(10))
    }

    private var phonePreviewModes: [DetailMode] {
        [.original, .cleaned]
    }

    private var startButtonTitle: String {
        if model.isRunning {
            return localizer.t(.processing)
        }
        return model.isBatchMode ? localizer.t(.startBatch) : localizer.t(.start)
    }

    private var fileButtonTitle: String {
        if model.isBatchMode {
            return localizer.t(.choosePDFs)
        }
        return localizer.t(.choosePDF)
    }

    private var canClearInputs: Bool {
        !model.isRunning && (model.inputURL != nil || !model.batchInputURLs.isEmpty)
    }

    private var canExportMark: Bool {
        model.inputURL != nil && !model.isRunning
    }

    private var pdfPickerAllowsMultipleSelection: Bool {
        enableAdvancedOptions || model.isBatchMode
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
            return pdfPickerAllowsMultipleSelection
        case .folder:
            return false
        }
    }

    private var activeAlert: ActiveAlert? {
        if let message = model.errorMessage {
            return .processError(message)
        }
        if let fileName = model.noMarksFileName {
            return .noMarks(fileName)
        }
        return nil
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
            importPickedFiles(items)
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
        .fileExporter(
            isPresented: $showMarkReportExporter,
            document: markReportDocument,
            contentType: .plainText,
            defaultFilename: markReportFilename
        ) { result in
            switch result {
            case .success(let savedURL):
                model.markMarkReportExportCompleted(destination: savedURL)
            case .failure(let error):
                model.errorMessage = error.localizedDescription
                model.status = localizer.format(.exportMarkFailed, error.localizedDescription)
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
        .alert(alertTitle(for: activeAlert), isPresented: Binding(
            get: { activeAlert != nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                    model.noMarksFileName = nil
                }
            }
        ), presenting: activeAlert) { alert in
            Button(localizer.t(.ok), role: .cancel) {
                switch alert {
                case .processError:
                    model.errorMessage = nil
                case .noMarks:
                    model.noMarksFileName = nil
                }
            }
        } message: { alert in
            switch alert {
            case .processError(let message):
                Text(message)
            case .noMarks(let fileName):
                Text(localizer.format(.noMarksFoundInFile, fileName))
            }
        }
        .onAppear {
            applySettingsToModeIfNeeded()
        }
        .onChange(of: enableAdvancedOptions) { _, _ in
            applySettingsToModeIfNeeded()
        }
        .onChange(of: preferBatchMode) { _, _ in
            applySettingsToModeIfNeeded()
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
                    Label(localizer.t(.files), systemImage: "house")
                }

            phonePreviewTab
                .tag(PhoneTab.preview)
                .tabItem {
                    Label(localizer.t(.preview), systemImage: "doc.text.image")
                }

            phoneSettingsTab
                .tag(PhoneTab.settings)
                .tabItem {
                    Label(localizer.t(.settings), systemImage: "gearshape")
                }
        }
        .tint(backgroundTheme.accentColor)
    }

    private var phoneHomeTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    phonePrimaryActions
                    filesSection
                    exportSection
                    if !model.isBatchMode {
                        pageRangeSection
                    }
                    annotationTypeSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(localizer.t(.files))
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
            .frame(maxWidth: .infinity, alignment: .leading)

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
                .disabled(!canClearInputs)
            }
        }
        .modifier(SidebarCardStyle())
    }

    private var phonePreviewTab: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isBatchMode ? localizer.t(.previewBatch) : localizer.t(.preview))
                        .font(.headline)
                    Text(detailSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if model.isBatchMode {
                    batchNavigator
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.thinMaterial)
                        )
                }

                Picker(localizer.t(.preview), selection: $detailMode) {
                    ForEach(phonePreviewModes) { mode in
                        Text(title(for: mode))
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch detailMode {
                    case .comparison, .original:
                        previewCard(title: localizer.t(.original), document: model.originalPreview)
                    case .cleaned:
                        previewCard(title: localizer.t(.cleaned), document: model.cleanedPreview)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(localizer.t(.preview))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if detailMode == .comparison {
                    detailMode = .original
                }
            }
        }
    }

    private var phoneSettingsTab: some View {
        NavigationStack {
            Form {
                Section {
                    phoneLanguageMenu
                    phoneBackgroundMenu
                } header: {
                    Text(localizer.t(.settings))
                }

                Section {
                    Toggle(localizer.t(.advancedOptions), isOn: $enableAdvancedOptions)
                        .toggleStyle(.switch)

                    Toggle(localizer.t(.preferBatch), isOn: $preferBatchMode)
                        .toggleStyle(.switch)
                        .disabled(!enableAdvancedOptions)

                    if enableAdvancedOptions {
                        Picker(localizer.t(.mode), selection: $model.processingMode) {
                            Text(localizer.t(.single)).tag(IOSProcessingMode.single)
                            Text(localizer.t(.batch)).tag(IOSProcessingMode.batch)
                        }
                        .pickerStyle(.segmented)

                        Text(model.isBatchMode ? localizer.t(.batchOnlyAllPages) : localizer.t(.singleSupportsPageRange))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(localizer.t(.mode))
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(localizer.t(.settings))
        }
    }

    private var phoneLanguageMenu: some View {
        Menu {
            ForEach(IOSAppLanguage.allCases) { language in
                Button(localizer.languageName(language)) {
                    appLanguageRaw = language.rawValue
                }
            }
        } label: {
            HStack {
                Text(localizer.t(.language))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(localizer.languageName(appLanguage))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private var phoneBackgroundMenu: some View {
        Menu {
            ForEach(IOSBackgroundTheme.allCases) { theme in
                Button(localizer.themeName(theme)) {
                    backgroundThemeRaw = theme.rawValue
                }
            }
        } label: {
            HStack {
                Text(localizer.t(.background))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(localizer.themeName(backgroundTheme))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            fixedTopPanel
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    filesSection
                    if !model.isBatchMode {
                        pageRangeSection
                    }
                    annotationTypeSection
                    exportSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            Divider()
            settingsSection
                .padding(12)
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fixedTopPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(backgroundTheme.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t(.appTitle))
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.inputURL?.lastPathComponent ?? localizer.t(.selectFileHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if isPad {
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
                    .disabled(!canClearInputs)
                }
            } else {
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
                    .disabled(!canClearInputs)
                }
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

    private var settingsSection: some View {
        DisclosureGroup(isExpanded: $showSettingsSection) {
            VStack(alignment: .leading, spacing: 10) {
                languageMenu
                backgroundMenu

                Toggle(localizer.t(.advancedOptions), isOn: $enableAdvancedOptions)
                    .toggleStyle(.switch)

                Toggle(localizer.t(.preferBatch), isOn: $preferBatchMode)
                    .toggleStyle(.switch)
                    .disabled(!enableAdvancedOptions)

                if enableAdvancedOptions {
                    Picker(localizer.t(.mode), selection: $model.processingMode) {
                        Text(localizer.t(.single)).tag(IOSProcessingMode.single)
                        Text(localizer.t(.batch)).tag(IOSProcessingMode.batch)
                    }
                    .pickerStyle(.segmented)

                    Text(model.isBatchMode ? localizer.t(.batchOnlyAllPages) : localizer.t(.singleSupportsPageRange))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.settings), icon: "slider.horizontal.3")
        }
        .modifier(SidebarCardStyle())
    }

    private var filesSection: some View {
        DisclosureGroup(isExpanded: $showFilesSection) {
            VStack(alignment: .leading, spacing: 8) {
                if model.isBatchMode {
                    Text(localizer.format(.filesCount, model.batchInputURLs.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.batchInputURLs.isEmpty {
                        Text(localizer.t(.batchEmpty))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.batchInputURLs.indices), id: \.self) { index in
                            let url = model.batchInputURLs[index]
                            batchRow(url: url, index: index)
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
        .modifier(SidebarCardStyle())
    }

    private var pageRangeSection: some View {
        DisclosureGroup(isExpanded: $showPageRangeSection) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(localizer.t(.pageRange), selection: $model.removalScope) {
                    Text(localizer.t(.allPages)).tag(IOSRemovalScope.all)
                    Text(localizer.t(.selectedPages)).tag(IOSRemovalScope.selected)
                }
                .pickerStyle(.segmented)

                if model.removalScope == .selected {
                    // 中文说明：支持输入 1-5,8,10 这种常见页范围语法。
                    TextField(localizer.t(.pageRangePlaceholder), text: $model.pageRangeInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            model.applyPageRangeInput()
                        }

                    HStack(spacing: 8) {
                        Button(localizer.t(.apply)) {
                            model.applyPageRangeInput()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(localizer.t(.selectAllPages)) {
                            model.selectAllPages()
                        }
                        .buttonStyle(.bordered)

                        Button(localizer.t(.clearPages)) {
                            model.clearSelectedPages()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(localizer.format(.selectedPagesSummary, model.selectedPages.count, model.pageCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.pageRange), icon: "text.page")
        }
        .modifier(SidebarCardStyle())
    }

    private var annotationTypeSection: some View {
        DisclosureGroup(isExpanded: $showTypeSection) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(localizer.t(.selectAllTypes)) {
                        model.selectAllTypes()
                    }
                    .buttonStyle(.bordered)

                    Button(localizer.t(.clearAllTypes)) {
                        model.clearAllTypes()
                    }
                    .buttonStyle(.bordered)
                }

                LazyVGrid(columns: typeColumns, alignment: .leading, spacing: 8) {
                    ForEach(visibleAnnotationKinds) { kind in
                        annotationTypeButton(kind)
                    }
                }

                if AnnotationKind.allCases.count > 10 {
                    Button(showAllAnnotationTypes ? localizer.t(.less) : localizer.t(.more)) {
                        showAllAnnotationTypes.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                Text(localizer.format(.selectedTypesSummary, model.selectedTypes.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.annotationTypes), icon: "checklist")
        }
        .modifier(SidebarCardStyle())
    }

    private var exportSection: some View {
        DisclosureGroup(isExpanded: $showExportSection) {
            VStack(alignment: .leading, spacing: 8) {
                if model.isBatchMode {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button(localizer.t(.saveBatch)) {
                                presentFolderPicker()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canSaveAsBatch)

                            Button(localizer.t(.replaceBatch), role: .destructive) {
                                pendingCriticalAction = .replaceBatch
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canReplaceOriginal)
                        }

                        HStack(spacing: 8) {
                            Button(localizer.t(.exportMark)) {
                                prepareMarkReportExport()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!canExportMark)

                            Button(localizer.t(.deleteBatch), role: .destructive) {
                                pendingCriticalAction = .deleteBatch
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canDeleteOriginal)
                        }
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
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button(localizer.t(.saveAs)) {
                                prepareSingleSaveAs()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canSaveAsSingle)

                            Button(localizer.t(.replaceOriginal), role: .destructive) {
                                pendingCriticalAction = .replaceSingle
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canReplaceOriginal)
                        }

                        HStack(spacing: 8) {
                            Button(localizer.t(.exportMark)) {
                                prepareMarkReportExport()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!canExportMark)

                            Button(localizer.t(.deleteOriginal), role: .destructive) {
                                pendingCriticalAction = .deleteSingle
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canDeleteOriginal)
                        }
                    }

                    Text(output.lastPathComponent)
                        .font(.footnote)
                        .lineLimit(2)
                    ShareLink(item: output) {
                        Label(localizer.t(.export), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button(localizer.t(.saveAs)) {
                                prepareSingleSaveAs()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(true)

                            Button(localizer.t(.replaceOriginal), role: .destructive) {}
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                                .disabled(true)
                        }

                        HStack(spacing: 8) {
                            Button(localizer.t(.exportMark)) {
                                prepareMarkReportExport()
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!canExportMark)

                            Button(localizer.t(.deleteOriginal), role: .destructive) {
                                pendingCriticalAction = .deleteSingle
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canDeleteOriginal)
                        }
                    }

                    Text(localizer.t(.exportHintSingle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text(localizer.t(.exportMarkHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            sectionHeader(title: localizer.t(.export), icon: "square.and.arrow.up")
        }
        .modifier(SidebarCardStyle())
    }

    private var languageMenu: some View {
        Menu {
            ForEach(IOSAppLanguage.allCases) { language in
                Button(localizer.languageName(language)) {
                    appLanguageRaw = language.rawValue
                }
            }
        } label: {
            settingChip(
                title: localizer.t(.language),
                value: localizer.languageName(appLanguage),
                icon: "globe"
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundMenu: some View {
        Menu {
            ForEach(IOSBackgroundTheme.allCases) { theme in
                Button(localizer.themeName(theme)) {
                    backgroundThemeRaw = theme.rawValue
                }
            }
        } label: {
            settingChip(
                title: localizer.t(.background),
                value: localizer.themeName(backgroundTheme),
                icon: "paintpalette"
            )
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.isBatchMode ? localizer.t(.previewBatch) : localizer.t(.preview))
                                .font(.title3.bold())
                            Text(detailSubtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if model.isBatchMode {
                        batchNavigator
                    }

                    switch detailMode {
                    case .comparison:
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                previewCard(title: localizer.t(.original), document: model.originalPreview)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                previewCard(title: localizer.t(.cleaned), document: model.cleanedPreview)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            VStack(spacing: 12) {
                                previewCard(title: localizer.t(.original), document: model.originalPreview)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                previewCard(title: localizer.t(.cleaned), document: model.cleanedPreview)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .original:
                        previewCard(title: localizer.t(.original), document: model.originalPreview)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .cleaned:
                        previewCard(title: localizer.t(.cleaned), document: model.cleanedPreview)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 6) {
            HStack {
                Spacer()
                fileLikeTabBar
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    private var fileLikeTabBar: some View {
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
                    Text(title(for: mode))
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
        .frame(maxWidth: 420, alignment: .center)
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
                        let previous = max(model.batchIndex - 1, 0)
                        model.switchToBatchIndex(previous)
                    } label: {
                        Label(localizer.t(.previous), systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.batchIndex <= 0)

                    Button {
                        let next = min(model.batchIndex + 1, model.batchInputURLs.count - 1)
                        model.switchToBatchIndex(next)
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

    private var detailSubtitle: String {
        if model.isBatchMode {
            return localizer.t(.previewSubtitleBatch)
        }
        if model.removalScope == .selected {
            return localizer.t(.previewSubtitleSelected)
        }
        return localizer.t(.previewSubtitleAll)
    }

    private func title(for mode: DetailMode) -> String {
        switch mode {
        case .comparison:
            return localizer.t(.comparison)
        case .original:
            return localizer.t(.original)
        case .cleaned:
            return localizer.t(.cleaned)
        }
    }

    @ViewBuilder
    private func annotationTypeButton(_ kind: AnnotationKind) -> some View {
        let selected = model.selectedTypes.contains(kind)
        let iconTint = selected ? backgroundTheme.accentColor : Color.black.opacity(0.72)
        let iconPlateFill = selected ? backgroundTheme.accentColor.opacity(0.20) : Color.black.opacity(0.06)
        let iconPlateStroke = selected ? backgroundTheme.accentColor.opacity(0.42) : Color.black.opacity(0.18)
        let buttonFill = selected ? backgroundTheme.accentColor.opacity(0.28) : Color.white.opacity(0.58)
        let buttonStroke = selected ? backgroundTheme.accentColor.opacity(0.90) : Color.black.opacity(0.14)
        let buttonShadow = selected ? backgroundTheme.accentColor.opacity(0.18) : Color.black.opacity(0.08)
        Button {
            model.toggleType(kind, enabled: !selected)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(iconPlateFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(iconPlateStroke, lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(selected ? 0.10 : 0.14), radius: 1.6, y: 1.0)

                Text(kind.title)
                    .font(.footnote)
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(backgroundTheme.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(buttonFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(buttonStroke, lineWidth: 1)
            )
            .shadow(color: buttonShadow, radius: selected ? 2.0 : 1.4, y: 0.8)
        }
        .buttonStyle(.plain)
    }

    private func toggleSidebar() {
        // 中文说明：通过 columnVisibility 切换侧栏显隐。
        withAnimation(.easeInOut(duration: 0.2)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    private func applySettingsToModeIfNeeded() {
        if !enableAdvancedOptions {
            model.processingMode = .single
            return
        }

        if preferBatchMode,
           model.processingMode == .single,
           model.inputURL == nil,
           model.batchInputURLs.isEmpty {
            model.processingMode = .batch
        }
    }

    private func presentPDFPicker() {
        presentImporter(.pdf)
    }

    private func presentFolderPicker() {
        presentImporter(.folder)
    }

    private func presentImporter(_ importer: ActiveImporter) {
        activeImporter = importer
        if showFileImporter {
            showFileImporter = false
            DispatchQueue.main.async {
                showFileImporter = true
            }
            return
        }
        showFileImporter = true
    }

    private func importPickedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if enableAdvancedOptions {
            model.handlePickedFiles(urls)
            return
        }

        model.processingMode = .single
        model.handlePickedFiles([urls[0]])
        if urls.count > 1 {
            model.status = localizer.t(.advancedOffMultiFileHint)
        }
    }

    private func prepareSingleSaveAs() {
        guard let payload = model.prepareSingleExportPayload() else { return }
        singleSaveDocument = PDFExportDocument(data: payload.data)
        singleSaveFilename = payload.filename
        showSingleSaveExporter = true
    }

    private func prepareMarkReportExport() {
        guard let payload = model.prepareMarkReportExportPayload() else { return }
        markReportDocument = TextExportDocument(data: payload.data)
        markReportFilename = payload.filename
        showMarkReportExporter = true
    }

    private func performCriticalAction(_ action: CriticalExportAction) {
        pendingCriticalAction = nil
        switch action {
        case .replaceSingle, .replaceBatch:
            model.replaceOriginals()
        case .deleteSingle, .deleteBatch:
            model.deleteOriginals()
        }
    }

    private func confirmationTitle(for action: CriticalExportAction?) -> String {
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

    private func confirmationMessage(for action: CriticalExportAction) -> String {
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

    private func alertTitle(for alert: ActiveAlert?) -> String {
        guard let alert else { return "" }
        switch alert {
        case .processError:
            return localizer.t(.processFailed)
        case .noMarks:
            return localizer.t(.noMarksFound)
        }
    }

    @ViewBuilder
    private func batchRow(url: URL, index: Int) -> some View {
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
                IOSPDFKitView(document: document)
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

    @ViewBuilder
    private func settingChip(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(backgroundTheme.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private struct PDFExportDocument: FileDocument {
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

private struct TextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

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

private struct SidebarCardStyle: ViewModifier {
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

private struct IOSPDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> IOSAdaptivePDFView {
        let view = IOSAdaptivePDFView()
        view.autoScales = false
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .systemBackground
        view.onBoundsDidChange = { [weak view] in
            guard let view else { return }
            context.coordinator.scheduleScaleUpdate(for: view)
        }
        view.document = nil
        view.document = document
        context.coordinator.scheduleScaleUpdate(for: view)
        return view
    }

    func updateUIView(_ uiView: IOSAdaptivePDFView, context: Context) {
        if uiView.document !== document {
            uiView.document = nil
            uiView.document = document
            uiView.goToFirstPage(nil)
            context.coordinator.scheduleScaleUpdate(for: uiView)
        }
    }

    static func dismantleUIView(_ uiView: IOSAdaptivePDFView, coordinator: Coordinator) {
        uiView.onBoundsDidChange = nil
        coordinator.cancelPendingScaleUpdate()
    }

    fileprivate static func applyDefaultScale(to view: PDFView) {
        let fitScale = view.scaleFactorForSizeToFit
        guard fitScale > 0 else {
            view.autoScales = true
            return
        }
        view.autoScales = false
        view.minScaleFactor = fitScale * 0.8
        view.maxScaleFactor = max(fitScale * 5, 4)
        view.scaleFactor = fitScale
    }

    final class Coordinator {
        private var pendingScaleWork: DispatchWorkItem?

        func scheduleScaleUpdate(for view: PDFView) {
            pendingScaleWork?.cancel()
            let work = DispatchWorkItem { [weak view] in
                guard let view else { return }
                IOSPDFKitView.applyDefaultScale(to: view)
            }
            pendingScaleWork = work
            DispatchQueue.main.async(execute: work)
        }

        func cancelPendingScaleUpdate() {
            pendingScaleWork?.cancel()
            pendingScaleWork = nil
        }
    }
}

private final class IOSAdaptivePDFView: PDFView {
    var onBoundsDidChange: (() -> Void)?
    private var lastBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        guard abs(size.width - lastBoundsSize.width) > 0.5 || abs(size.height - lastBoundsSize.height) > 0.5 else {
            return
        }
        lastBoundsSize = size
        onBoundsDidChange?()
    }
}

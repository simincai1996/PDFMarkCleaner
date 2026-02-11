import Foundation
import SwiftUI

enum IOSAppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chineseSimplified
    case chineseTraditional
    case german
    case spanish

    var id: String { rawValue }
}

enum IOSBackgroundTheme: String, CaseIterable, Identifiable {
    case frost
    case sky
    case mint
    case peach
    case sand

    var id: String { rawValue }

    var topColor: Color {
        switch self {
        case .frost:
            return Color(red: 0.95, green: 0.97, blue: 1.0)
        case .sky:
            return Color(red: 0.92, green: 0.97, blue: 1.0)
        case .mint:
            return Color(red: 0.92, green: 0.99, blue: 0.97)
        case .peach:
            return Color(red: 0.99, green: 0.96, blue: 0.93)
        case .sand:
            return Color(red: 0.98, green: 0.97, blue: 0.92)
        }
    }

    var bottomColor: Color {
        switch self {
        case .frost:
            return Color(red: 0.88, green: 0.93, blue: 0.98)
        case .sky:
            return Color(red: 0.86, green: 0.93, blue: 0.98)
        case .mint:
            return Color(red: 0.85, green: 0.96, blue: 0.93)
        case .peach:
            return Color(red: 0.98, green: 0.90, blue: 0.87)
        case .sand:
            return Color(red: 0.95, green: 0.93, blue: 0.86)
        }
    }

    var accentColor: Color {
        switch self {
        case .frost:
            return Color(red: 0.36, green: 0.55, blue: 0.98)
        case .sky:
            return Color(red: 0.25, green: 0.63, blue: 0.98)
        case .mint:
            return Color(red: 0.20, green: 0.70, blue: 0.55)
        case .peach:
            return Color(red: 0.97, green: 0.55, blue: 0.45)
        case .sand:
            return Color(red: 0.90, green: 0.65, blue: 0.35)
        }
    }
}

enum IOSLKey {
    case appTitle
    case choosePDF
    case choosePDFs
    case start
    case startBatch
    case processing
    case clear
    case mode
    case single
    case batch
    case files
    case filesCount
    case noFileSelected
    case pageRange
    case allPages
    case selectedPages
    case pageRangePlaceholder
    case apply
    case selectAllPages
    case clearPages
    case selectedPagesSummary
    case annotationTypes
    case selectAllTypes
    case clearAllTypes
    case selectedTypesSummary
    case export
    case exportHintSingle
    case exportHintBatch
    case language
    case background
    case advancedOptions
    case preferBatch
    case batchOnlyAllPages
    case singleSupportsPageRange
    case preview
    case previewBatch
    case previewSubtitleBatch
    case previewSubtitleAll
    case previewSubtitleSelected
    case comparison
    case original
    case cleaned
    case collapseSidebar
    case expandSidebar
    case batchEmpty
    case previous
    case next
    case itemIndex
    case processFailed
    case pickFailed
    case advancedOffMultiFileHint
    case settings
    case selectFileHint
    case more
    case less
    case noPreview
}

struct IOSLocalizer {
    let language: IOSAppLanguage

    private var resolved: IOSAppLanguage {
        if language == .system {
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            if preferred.contains("zh-hant") || preferred.contains("zh-tw") || preferred.contains("zh-hk") || preferred.contains("zh-mo") {
                return .chineseTraditional
            }
            if preferred.contains("zh-hans") || preferred.contains("zh-cn") || preferred.contains("zh-sg") || preferred.hasPrefix("zh") {
                return .chineseSimplified
            }
            if preferred.hasPrefix("de") {
                return .german
            }
            if preferred.hasPrefix("es") {
                return .spanish
            }
            return .english
        }
        return language
    }

    func t(_ key: IOSLKey) -> String {
        switch resolved {
        case .english, .german, .spanish:
            return english(key)
        case .chineseSimplified:
            return chineseSimplified(key)
        case .chineseTraditional:
            return chineseTraditional(key)
        case .system:
            return english(key)
        }
    }

    func format(_ key: IOSLKey, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }

    func languageName(_ language: IOSAppLanguage) -> String {
        switch resolved {
        case .chineseSimplified:
            switch language {
            case .system: return "跟随系统"
            case .english: return "英文"
            case .chineseSimplified: return "简体中文"
            case .chineseTraditional: return "繁体中文"
            case .german: return "德语"
            case .spanish: return "西班牙语"
            }
        case .chineseTraditional:
            switch language {
            case .system: return "跟隨系統"
            case .english: return "英文"
            case .chineseSimplified: return "簡體中文"
            case .chineseTraditional: return "繁體中文"
            case .german: return "德文"
            case .spanish: return "西班牙文"
            }
        case .english, .german, .spanish, .system:
            switch language {
            case .system: return "System"
            case .english: return "English"
            case .chineseSimplified: return "Chinese (Simplified)"
            case .chineseTraditional: return "Chinese (Traditional)"
            case .german: return "German"
            case .spanish: return "Spanish"
            }
        }
    }

    func themeName(_ theme: IOSBackgroundTheme) -> String {
        switch resolved {
        case .chineseSimplified:
            switch theme {
            case .frost: return "清霜"
            case .sky: return "晴空"
            case .mint: return "薄荷"
            case .peach: return "蜜桃"
            case .sand: return "暖沙"
            }
        case .chineseTraditional:
            switch theme {
            case .frost: return "清霜"
            case .sky: return "晴空"
            case .mint: return "薄荷"
            case .peach: return "蜜桃"
            case .sand: return "暖沙"
            }
        case .english, .german, .spanish, .system:
            switch theme {
            case .frost: return "Frost"
            case .sky: return "Sky"
            case .mint: return "Mint"
            case .peach: return "Peach"
            case .sand: return "Sand"
            }
        }
    }

    private func english(_ key: IOSLKey) -> String {
        switch key {
        case .appTitle: return "PDF Mark Cleaner"
        case .choosePDF: return "Choose PDF"
        case .choosePDFs: return "Choose PDFs"
        case .start: return "Start"
        case .startBatch: return "Start Batch"
        case .processing: return "Processing..."
        case .clear: return "Clear"
        case .mode: return "Mode"
        case .single: return "Single"
        case .batch: return "Batch"
        case .files: return "Files"
        case .filesCount: return "Files: %d"
        case .noFileSelected: return "No file selected"
        case .pageRange: return "Page Range"
        case .allPages: return "All Pages"
        case .selectedPages: return "Selected Pages"
        case .pageRangePlaceholder: return "e.g. 1-5,8,10"
        case .apply: return "Apply"
        case .selectAllPages: return "All"
        case .clearPages: return "Clear"
        case .selectedPagesSummary: return "Selected %d / %d pages"
        case .annotationTypes: return "Annotation Types"
        case .selectAllTypes: return "All"
        case .clearAllTypes: return "None"
        case .selectedTypesSummary: return "Selected %d types"
        case .export: return "Export"
        case .exportHintSingle: return "You can share the cleaned file after processing."
        case .exportHintBatch: return "Batch outputs can be shared one by one after processing."
        case .language: return "Language"
        case .background: return "Background"
        case .advancedOptions: return "Advanced"
        case .preferBatch: return "Prefer Batch"
        case .batchOnlyAllPages: return "Batch mode only supports all pages."
        case .singleSupportsPageRange: return "Single mode supports page range."
        case .preview: return "Preview"
        case .previewBatch: return "Batch Preview"
        case .previewSubtitleBatch: return "Inspect the current file in this batch."
        case .previewSubtitleAll: return "All pages are selected for cleanup."
        case .previewSubtitleSelected: return "Only selected pages will be processed."
        case .comparison: return "Compared"
        case .original: return "Original"
        case .cleaned: return "Clean"
        case .collapseSidebar: return "Collapse"
        case .expandSidebar: return "Expand"
        case .batchEmpty: return "Batch list is empty."
        case .previous: return "Previous"
        case .next: return "Next"
        case .itemIndex: return "Item %d"
        case .processFailed: return "Process Failed"
        case .pickFailed: return "Failed to select files."
        case .advancedOffMultiFileHint: return "Advanced batch is off; only the first file was imported."
        case .settings: return "Settings"
        case .selectFileHint: return "Select PDF first"
        case .more: return "More..."
        case .less: return "Less"
        case .noPreview: return "No preview"
        }
    }

    private func chineseSimplified(_ key: IOSLKey) -> String {
        switch key {
        case .appTitle: return "PDF 标记清理器"
        case .choosePDF: return "选择 PDF"
        case .choosePDFs: return "选择 PDF（多选）"
        case .start: return "开始清理"
        case .startBatch: return "开始批处理"
        case .processing: return "处理中..."
        case .clear: return "清空"
        case .mode: return "模式"
        case .single: return "单文件"
        case .batch: return "批处理"
        case .files: return "文件"
        case .filesCount: return "文件：%d"
        case .noFileSelected: return "未选择文件"
        case .pageRange: return "页范围"
        case .allPages: return "全部页面"
        case .selectedPages: return "指定页面"
        case .pageRangePlaceholder: return "例如 1-5,8,10"
        case .apply: return "应用"
        case .selectAllPages: return "全选"
        case .clearPages: return "清空"
        case .selectedPagesSummary: return "已选 %d / %d 页"
        case .annotationTypes: return "注释类型"
        case .selectAllTypes: return "全选"
        case .clearAllTypes: return "清空"
        case .selectedTypesSummary: return "已选 %d 类"
        case .export: return "导出"
        case .exportHintSingle: return "处理完成后可分享导出文件。"
        case .exportHintBatch: return "批处理完成后可逐个分享输出文件。"
        case .language: return "语言"
        case .background: return "背景"
        case .advancedOptions: return "高级"
        case .preferBatch: return "优先批处理"
        case .batchOnlyAllPages: return "批处理仅支持全页清理。"
        case .singleSupportsPageRange: return "单文件支持页范围设置。"
        case .preview: return "文件预览"
        case .previewBatch: return "批处理预览"
        case .previewSubtitleBatch: return "可在此检查当前批处理文件。"
        case .previewSubtitleAll: return "当前处理全部页面。"
        case .previewSubtitleSelected: return "当前仅处理指定页面。"
        case .comparison: return "对比"
        case .original: return "原文件"
        case .cleaned: return "清理后"
        case .collapseSidebar: return "收起"
        case .expandSidebar: return "展开"
        case .batchEmpty: return "批处理列表为空。"
        case .previous: return "上一个"
        case .next: return "下一个"
        case .itemIndex: return "第 %d 个"
        case .processFailed: return "处理失败"
        case .pickFailed: return "文件选择失败。"
        case .advancedOffMultiFileHint: return "已关闭高级批处理，仅导入第一个文件。"
        case .settings: return "设置"
        case .selectFileHint: return "请先选择 PDF"
        case .more: return "更多..."
        case .less: return "收起"
        case .noPreview: return "暂无预览"
        }
    }

    private func chineseTraditional(_ key: IOSLKey) -> String {
        switch key {
        case .appTitle: return "PDF 標記清理器"
        case .choosePDF: return "選擇 PDF"
        case .choosePDFs: return "選擇 PDF（可多選）"
        case .start: return "開始清理"
        case .startBatch: return "開始批次處理"
        case .processing: return "處理中..."
        case .clear: return "清空"
        case .mode: return "模式"
        case .single: return "單檔"
        case .batch: return "批次"
        case .files: return "檔案"
        case .filesCount: return "檔案：%d"
        case .noFileSelected: return "未選擇檔案"
        case .pageRange: return "頁範圍"
        case .allPages: return "全部頁面"
        case .selectedPages: return "指定頁面"
        case .pageRangePlaceholder: return "例如 1-5,8,10"
        case .apply: return "套用"
        case .selectAllPages: return "全選"
        case .clearPages: return "清空"
        case .selectedPagesSummary: return "已選 %d / %d 頁"
        case .annotationTypes: return "註解類型"
        case .selectAllTypes: return "全選"
        case .clearAllTypes: return "清空"
        case .selectedTypesSummary: return "已選 %d 類"
        case .export: return "匯出"
        case .exportHintSingle: return "處理完成後可分享匯出檔案。"
        case .exportHintBatch: return "批次完成後可逐一分享輸出檔。"
        case .language: return "語言"
        case .background: return "背景"
        case .advancedOptions: return "進階"
        case .preferBatch: return "優先批次"
        case .batchOnlyAllPages: return "批次模式僅支援全部頁面。"
        case .singleSupportsPageRange: return "單檔模式可設定頁範圍。"
        case .preview: return "檔案預覽"
        case .previewBatch: return "批次預覽"
        case .previewSubtitleBatch: return "可在此檢查目前批次檔案。"
        case .previewSubtitleAll: return "目前處理全部頁面。"
        case .previewSubtitleSelected: return "目前僅處理指定頁面。"
        case .comparison: return "對比"
        case .original: return "原始"
        case .cleaned: return "清理後"
        case .collapseSidebar: return "收起"
        case .expandSidebar: return "展開"
        case .batchEmpty: return "批次列表為空。"
        case .previous: return "上一個"
        case .next: return "下一個"
        case .itemIndex: return "第 %d 個"
        case .processFailed: return "處理失敗"
        case .pickFailed: return "檔案選擇失敗。"
        case .advancedOffMultiFileHint: return "已關閉進階批次，僅匯入第一個檔案。"
        case .settings: return "設定"
        case .selectFileHint: return "請先選擇 PDF"
        case .more: return "更多..."
        case .less: return "收起"
        case .noPreview: return "暫無預覽"
        }
    }
}

struct IOSGlassBackground: View {
    let theme: IOSBackgroundTheme

    var body: some View {
        LinearGradient(
            colors: [theme.topColor, theme.bottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.48))
                    .blur(radius: 88)
                    .offset(x: -220, y: -170)
                Circle()
                    .fill(theme.accentColor.opacity(0.20))
                    .blur(radius: 110)
                    .offset(x: 250, y: 250)
            }
        )
    }
}

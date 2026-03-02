import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case chineseSimplified
    case chineseTraditional
    case german
    case spanish

    var id: String { rawValue }
}

enum LKey {
    case toolMarkClean
    case toolUnlock
    case appTitle
    case files
    case input
    case selectPDF
    case clear
    case output
    case selectOutput
    case auto
    case noFileSelected
    case action
    case processing
    case start
    case save
    case exportMark
    case replace
    case deleteOriginal
    case annotationTypes
    case all
    case none
    case removePages
    case pagesPlaceholder
    case apply
    case selectAll
    case selectedCount
    case navigation
    case page
    case markedPages
    case prevMarked
    case nextMarked
    case markedCount
    case noMarksFound
    case annotationCounts
    case allPages
    case currentPage
    case selectedPages
    case zoom
    case reset
    case size
    case current
    case estimated
    case estimating
    case outdated
    case estimateSize
    case reEstimate
    case noPreview
    case original
    case beforeCleanup
    case afterClean
    case expectedResult
    case beforeUnlock
    case afterUnlock
    case expectedUnlocked
    case settingsTitle
    case language
    case systemLanguage
    case english
    case chineseSimplified
    case chineseTraditional
    case german
    case spanish
    case advancedOptions
    case mode
    case single
    case batch
    case selectPDFs
    case filesSelected
    case currentFile
    case previewFile
    case startBatch
    case unlockPassword
    case passwordPlaceholder
    case locked
    case unlocked
    case batchPasswordHint
    case sameAsInputFolder
    case dropPDFFiles
    case noNewPDFFilesAdded
    case filesAdded
    case removedFromBatch
    case removeFromBatchList
    case batchDoneWithRenamed
    case background
    case themeFrost
    case themeSky
    case themeMint
    case themePeach
    case themeSand
}

struct Localizer {
    let language: AppLanguage

    private var resolved: AppLanguage {
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

    func t(_ key: LKey) -> String {
        switch resolved {
        case .english:
            return english(key)
        case .chineseSimplified:
            return chinese(key)
        case .chineseTraditional:
            return chineseTraditional(key)
        case .german:
            return german(key)
        case .spanish:
            return spanish(key)
        case .system:
            return english(key)
        }
    }

    func format(_ key: LKey, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }

    private func english(_ key: LKey) -> String {
        switch key {
        case .toolMarkClean: return "PDF Mark Clean"
        case .toolUnlock: return "PDF Unlock"
        case .appTitle: return "PDF Mark Cleaner"
        case .files: return "Files"
        case .input: return "Input"
        case .selectPDF: return "Select PDF"
        case .clear: return "Clear"
        case .output: return "Output"
        case .selectOutput: return "Select Output"
        case .auto: return "Auto"
        case .noFileSelected: return "No file selected"
        case .action: return "Action"
        case .processing: return "Processing..."
        case .start: return "Start"
        case .save: return "Save"
        case .exportMark: return "Export Mark"
        case .replace: return "Replace"
        case .deleteOriginal: return "Delete Original"
        case .annotationTypes: return "Annotation Types"
        case .all: return "All"
        case .none: return "None"
        case .removePages: return "Remove Pages"
        case .pagesPlaceholder: return "Pages (1-5,8,10)"
        case .apply: return "Apply"
        case .selectAll: return "Select All"
        case .selectedCount: return "Selected: %d"
        case .navigation: return "Navigation"
        case .page: return "Page"
        case .markedPages: return "Marked Pages"
        case .prevMarked: return "Prev Marked"
        case .nextMarked: return "Next Marked"
        case .markedCount: return "Marked: %d"
        case .noMarksFound: return "No marks found"
        case .annotationCounts: return "Annotation Counts"
        case .allPages: return "All Pages"
        case .currentPage: return "Current Page"
        case .selectedPages: return "Selected Pages"
        case .zoom: return "Zoom"
        case .reset: return "Reset"
        case .size: return "Size"
        case .current: return "Current"
        case .estimated: return "Estimated"
        case .estimating: return "Estimating..."
        case .outdated: return "Outdated"
        case .estimateSize: return "Estimate Size"
        case .reEstimate: return "Re-estimate"
        case .noPreview: return "No preview"
        case .original: return "Original"
        case .beforeCleanup: return "Before cleanup"
        case .afterClean: return "After Clean"
        case .expectedResult: return "Expected result"
        case .beforeUnlock: return "Before unlock"
        case .afterUnlock: return "After unlock"
        case .expectedUnlocked: return "Expected unlocked result"
        case .settingsTitle: return "Settings"
        case .language: return "Language"
        case .systemLanguage: return "System"
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .advancedOptions: return "Advanced Options"
        case .mode: return "Mode"
        case .single: return "Single"
        case .batch: return "Batch"
        case .selectPDFs: return "Select PDFs"
        case .filesSelected: return "Files: %d"
        case .currentFile: return "Current File"
        case .previewFile: return "Preview File"
        case .startBatch: return "Start Batch"
        case .unlockPassword: return "Password"
        case .passwordPlaceholder: return "Password (for locked PDF)"
        case .locked: return "Current file is locked"
        case .unlocked: return "Current file is not locked"
        case .batchPasswordHint: return "One password is used for all locked PDFs in batch mode."
        case .sameAsInputFolder: return "Same as input folder"
        case .dropPDFFiles: return "Please drop PDF files."
        case .noNewPDFFilesAdded: return "No new PDF files added."
        case .filesAdded: return "Added: %d file(s)"
        case .removedFromBatch: return "Removed from batch: %@"
        case .removeFromBatchList: return "Remove from batch list"
        case .batchDoneWithRenamed: return "Batch done: %d files (renamed: %d)"
        case .background: return "Background"
        case .themeFrost: return "Frost"
        case .themeSky: return "Sky"
        case .themeMint: return "Mint"
        case .themePeach: return "Peach"
        case .themeSand: return "Sand"
        }
    }

    private func chinese(_ key: LKey) -> String {
        switch key {
        case .toolMarkClean: return "PDF 标记清理"
        case .toolUnlock: return "PDF 解锁"
        case .appTitle: return "PDF 标记清理器"
        case .files: return "文件"
        case .input: return "输入"
        case .selectPDF: return "选择 PDF"
        case .clear: return "清空"
        case .output: return "输出"
        case .selectOutput: return "选择输出"
        case .auto: return "自动"
        case .noFileSelected: return "未选择文件"
        case .action: return "操作"
        case .processing: return "处理中..."
        case .start: return "开始"
        case .save: return "保存"
        case .exportMark: return "导出标记"
        case .replace: return "替换"
        case .deleteOriginal: return "删除原文件"
        case .annotationTypes: return "标记类型"
        case .all: return "全选"
        case .none: return "全不选"
        case .removePages: return "清除页面"
        case .pagesPlaceholder: return "页码 (1-5,8,10)"
        case .apply: return "应用"
        case .selectAll: return "全选"
        case .selectedCount: return "已选：%d"
        case .navigation: return "导航"
        case .page: return "页码"
        case .markedPages: return "含标记页面"
        case .prevMarked: return "上一处标记"
        case .nextMarked: return "下一处标记"
        case .markedCount: return "标记：%d"
        case .noMarksFound: return "未找到标记"
        case .annotationCounts: return "标记统计"
        case .allPages: return "全部页面"
        case .currentPage: return "当前页面"
        case .selectedPages: return "已选页面"
        case .zoom: return "缩放"
        case .reset: return "重置"
        case .size: return "大小"
        case .current: return "当前"
        case .estimated: return "预计"
        case .estimating: return "计算中..."
        case .outdated: return "已过期"
        case .estimateSize: return "估算大小"
        case .reEstimate: return "重新估算"
        case .noPreview: return "暂无预览"
        case .original: return "原始"
        case .beforeCleanup: return "清理前"
        case .afterClean: return "清理后"
        case .expectedResult: return "预期结果"
        case .beforeUnlock: return "解锁前"
        case .afterUnlock: return "解锁后"
        case .expectedUnlocked: return "预期解锁结果"
        case .settingsTitle: return "设置"
        case .language: return "语言"
        case .systemLanguage: return "跟随系统"
        case .english: return "英文"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁体中文"
        case .german: return "德语"
        case .spanish: return "西班牙语"
        case .advancedOptions: return "高级选项"
        case .mode: return "模式"
        case .single: return "单个"
        case .batch: return "批量"
        case .selectPDFs: return "选择 PDF"
        case .filesSelected: return "文件：%d"
        case .currentFile: return "当前文件"
        case .previewFile: return "预览文件"
        case .startBatch: return "开始批量"
        case .unlockPassword: return "密码"
        case .passwordPlaceholder: return "密码（用于加密 PDF）"
        case .locked: return "当前文件已加密"
        case .unlocked: return "当前文件未加密"
        case .batchPasswordHint: return "批量模式下将对所有加密文件使用同一密码。"
        case .sameAsInputFolder: return "与输入文件夹相同"
        case .dropPDFFiles: return "请拖入 PDF 文件。"
        case .noNewPDFFilesAdded: return "没有新增 PDF 文件。"
        case .filesAdded: return "已添加：%d 个文件"
        case .removedFromBatch: return "已从批量列表移除：%@"
        case .removeFromBatchList: return "从批量列表移除"
        case .batchDoneWithRenamed: return "批量完成：%d 个文件（重命名：%d）"
        case .background: return "背景"
        case .themeFrost: return "清霜"
        case .themeSky: return "晴空"
        case .themeMint: return "薄荷"
        case .themePeach: return "蜜桃"
        case .themeSand: return "暖沙"
        }
    }

    private func chineseTraditional(_ key: LKey) -> String {
        switch key {
        case .toolMarkClean: return "PDF 標記清理"
        case .toolUnlock: return "PDF 解鎖"
        case .appTitle: return "PDF 標記清理器"
        case .files: return "檔案"
        case .input: return "輸入"
        case .selectPDF: return "選擇 PDF"
        case .clear: return "清空"
        case .output: return "輸出"
        case .selectOutput: return "選擇輸出"
        case .auto: return "自動"
        case .noFileSelected: return "未選擇檔案"
        case .action: return "操作"
        case .processing: return "處理中..."
        case .start: return "開始"
        case .save: return "儲存"
        case .exportMark: return "匯出標記"
        case .replace: return "取代"
        case .deleteOriginal: return "刪除原檔"
        case .annotationTypes: return "標記類型"
        case .all: return "全選"
        case .none: return "全不選"
        case .removePages: return "清除頁面"
        case .pagesPlaceholder: return "頁碼 (1-5,8,10)"
        case .apply: return "套用"
        case .selectAll: return "全選"
        case .selectedCount: return "已選：%d"
        case .navigation: return "導覽"
        case .page: return "頁碼"
        case .markedPages: return "含標記頁面"
        case .prevMarked: return "上一處標記"
        case .nextMarked: return "下一處標記"
        case .markedCount: return "標記：%d"
        case .noMarksFound: return "未找到標記"
        case .annotationCounts: return "標記統計"
        case .allPages: return "全部頁面"
        case .currentPage: return "目前頁面"
        case .selectedPages: return "已選頁面"
        case .zoom: return "縮放"
        case .reset: return "重設"
        case .size: return "大小"
        case .current: return "目前"
        case .estimated: return "預估"
        case .estimating: return "計算中..."
        case .outdated: return "已過期"
        case .estimateSize: return "估算大小"
        case .reEstimate: return "重新估算"
        case .noPreview: return "無預覽"
        case .original: return "原始"
        case .beforeCleanup: return "清理前"
        case .afterClean: return "清理後"
        case .expectedResult: return "預期結果"
        case .beforeUnlock: return "解鎖前"
        case .afterUnlock: return "解鎖後"
        case .expectedUnlocked: return "預期解鎖結果"
        case .settingsTitle: return "設定"
        case .language: return "語言"
        case .systemLanguage: return "跟隨系統"
        case .english: return "英文"
        case .chineseSimplified: return "簡體中文"
        case .chineseTraditional: return "繁體中文"
        case .german: return "德語"
        case .spanish: return "西班牙語"
        case .advancedOptions: return "高級選項"
        case .mode: return "模式"
        case .single: return "單個"
        case .batch: return "批量"
        case .selectPDFs: return "選擇 PDF"
        case .filesSelected: return "檔案：%d"
        case .currentFile: return "目前檔案"
        case .previewFile: return "預覽檔案"
        case .startBatch: return "開始批量"
        case .unlockPassword: return "密碼"
        case .passwordPlaceholder: return "密碼（用於加密 PDF）"
        case .locked: return "目前檔案已加密"
        case .unlocked: return "目前檔案未加密"
        case .batchPasswordHint: return "批量模式會對所有加密檔案使用同一組密碼。"
        case .sameAsInputFolder: return "與輸入資料夾相同"
        case .dropPDFFiles: return "請拖入 PDF 檔案。"
        case .noNewPDFFilesAdded: return "沒有新增 PDF 檔案。"
        case .filesAdded: return "已新增：%d 個檔案"
        case .removedFromBatch: return "已從批量清單移除：%@"
        case .removeFromBatchList: return "從批量清單移除"
        case .batchDoneWithRenamed: return "批量完成：%d 個檔案（重新命名：%d）"
        case .background: return "背景"
        case .themeFrost: return "清霜"
        case .themeSky: return "晴空"
        case .themeMint: return "薄荷"
        case .themePeach: return "蜜桃"
        case .themeSand: return "暖沙"
        }
    }

    private func german(_ key: LKey) -> String {
        switch key {
        case .toolMarkClean: return "PDF-Marken reinigen"
        case .toolUnlock: return "PDF entsperren"
        case .appTitle: return "PDF-Markierungen bereinigen"
        case .files: return "Dateien"
        case .input: return "Eingabe"
        case .selectPDF: return "PDF wählen"
        case .clear: return "Leeren"
        case .output: return "Ausgabe"
        case .selectOutput: return "Ausgabe wählen"
        case .auto: return "Auto"
        case .noFileSelected: return "Keine Datei ausgewählt"
        case .action: return "Aktion"
        case .processing: return "Verarbeitung..."
        case .start: return "Start"
        case .save: return "Speichern"
        case .exportMark: return "Markierungen exportieren"
        case .replace: return "Ersetzen"
        case .deleteOriginal: return "Original löschen"
        case .annotationTypes: return "Anmerkungstypen"
        case .all: return "Alle"
        case .none: return "Keine"
        case .removePages: return "Seiten bereinigen"
        case .pagesPlaceholder: return "Seiten (1-5,8,10)"
        case .apply: return "Anwenden"
        case .selectAll: return "Alle auswählen"
        case .selectedCount: return "Ausgewählt: %d"
        case .navigation: return "Navigation"
        case .page: return "Seite"
        case .markedPages: return "Markierte Seiten"
        case .prevMarked: return "Vorige Markierung"
        case .nextMarked: return "Nächste Markierung"
        case .markedCount: return "Markiert: %d"
        case .noMarksFound: return "Keine Markierungen gefunden"
        case .annotationCounts: return "Markierungsanzahl"
        case .allPages: return "Alle Seiten"
        case .currentPage: return "Aktuelle Seite"
        case .selectedPages: return "Ausgewählte Seiten"
        case .zoom: return "Zoom"
        case .reset: return "Zurücksetzen"
        case .size: return "Größe"
        case .current: return "Aktuell"
        case .estimated: return "Geschätzt"
        case .estimating: return "Berechnen..."
        case .outdated: return "Veraltet"
        case .estimateSize: return "Größe schätzen"
        case .reEstimate: return "Neu schätzen"
        case .noPreview: return "Keine Vorschau"
        case .original: return "Original"
        case .beforeCleanup: return "Vor der Bereinigung"
        case .afterClean: return "Nach der Bereinigung"
        case .expectedResult: return "Erwartetes Ergebnis"
        case .beforeUnlock: return "Vor dem Entsperren"
        case .afterUnlock: return "Nach dem Entsperren"
        case .expectedUnlocked: return "Erwartetes entsperrtes Ergebnis"
        case .settingsTitle: return "Einstellungen"
        case .language: return "Sprache"
        case .systemLanguage: return "System"
        case .english: return "Englisch"
        case .chineseSimplified: return "Chinesisch (vereinfacht)"
        case .chineseTraditional: return "Chinesisch (traditionell)"
        case .german: return "Deutsch"
        case .spanish: return "Spanisch"
        case .advancedOptions: return "Erweiterte Optionen"
        case .mode: return "Modus"
        case .single: return "Einzeln"
        case .batch: return "Stapel"
        case .selectPDFs: return "PDFs wählen"
        case .filesSelected: return "Dateien: %d"
        case .currentFile: return "Aktuelle Datei"
        case .previewFile: return "Vorschau-Datei"
        case .startBatch: return "Stapel starten"
        case .unlockPassword: return "Passwort"
        case .passwordPlaceholder: return "Passwort (für geschütztes PDF)"
        case .locked: return "Aktuelle Datei ist geschützt"
        case .unlocked: return "Aktuelle Datei ist nicht geschützt"
        case .batchPasswordHint: return "Im Stapelmodus wird ein Passwort für alle geschützten PDFs verwendet."
        case .sameAsInputFolder: return "Wie Eingabeordner"
        case .dropPDFFiles: return "Bitte PDF-Dateien hier ablegen."
        case .noNewPDFFilesAdded: return "Keine neuen PDF-Dateien hinzugefügt."
        case .filesAdded: return "Hinzugefügt: %d Datei(en)"
        case .removedFromBatch: return "Aus Stapel entfernt: %@"
        case .removeFromBatchList: return "Aus Stapelliste entfernen"
        case .batchDoneWithRenamed: return "Stapel abgeschlossen: %d Dateien (umbenannt: %d)"
        case .background: return "Hintergrund"
        case .themeFrost: return "Frost"
        case .themeSky: return "Himmel"
        case .themeMint: return "Minze"
        case .themePeach: return "Pfirsich"
        case .themeSand: return "Sand"
        }
    }

    private func spanish(_ key: LKey) -> String {
        switch key {
        case .toolMarkClean: return "Limpieza de marcas PDF"
        case .toolUnlock: return "Desbloquear PDF"
        case .appTitle: return "Limpiador de marcas PDF"
        case .files: return "Archivos"
        case .input: return "Entrada"
        case .selectPDF: return "Seleccionar PDF"
        case .clear: return "Limpiar"
        case .output: return "Salida"
        case .selectOutput: return "Seleccionar salida"
        case .auto: return "Auto"
        case .noFileSelected: return "Ningún archivo seleccionado"
        case .action: return "Acción"
        case .processing: return "Procesando..."
        case .start: return "Iniciar"
        case .save: return "Guardar"
        case .exportMark: return "Exportar marcas"
        case .replace: return "Reemplazar"
        case .deleteOriginal: return "Eliminar original"
        case .annotationTypes: return "Tipos de anotación"
        case .all: return "Todo"
        case .none: return "Ninguno"
        case .removePages: return "Eliminar páginas"
        case .pagesPlaceholder: return "Páginas (1-5,8,10)"
        case .apply: return "Aplicar"
        case .selectAll: return "Seleccionar todo"
        case .selectedCount: return "Seleccionado: %d"
        case .navigation: return "Navegación"
        case .page: return "Página"
        case .markedPages: return "Páginas marcadas"
        case .prevMarked: return "Marca anterior"
        case .nextMarked: return "Siguiente marca"
        case .markedCount: return "Marcado: %d"
        case .noMarksFound: return "No se encontraron marcas"
        case .annotationCounts: return "Conteo de marcas"
        case .allPages: return "Todas las páginas"
        case .currentPage: return "Página actual"
        case .selectedPages: return "Páginas seleccionadas"
        case .zoom: return "Zoom"
        case .reset: return "Restablecer"
        case .size: return "Tamaño"
        case .current: return "Actual"
        case .estimated: return "Estimado"
        case .estimating: return "Calculando..."
        case .outdated: return "Desactualizado"
        case .estimateSize: return "Estimar tamaño"
        case .reEstimate: return "Reestimar"
        case .noPreview: return "Sin vista previa"
        case .original: return "Original"
        case .beforeCleanup: return "Antes de limpiar"
        case .afterClean: return "Después de limpiar"
        case .expectedResult: return "Resultado esperado"
        case .beforeUnlock: return "Antes de desbloquear"
        case .afterUnlock: return "Después de desbloquear"
        case .expectedUnlocked: return "Resultado esperado desbloqueado"
        case .settingsTitle: return "Configuración"
        case .language: return "Idioma"
        case .systemLanguage: return "Sistema"
        case .english: return "Inglés"
        case .chineseSimplified: return "Chino (simplificado)"
        case .chineseTraditional: return "Chino (tradicional)"
        case .german: return "Alemán"
        case .spanish: return "Español"
        case .advancedOptions: return "Opciones avanzadas"
        case .mode: return "Modo"
        case .single: return "Único"
        case .batch: return "Lote"
        case .selectPDFs: return "Seleccionar PDFs"
        case .filesSelected: return "Archivos: %d"
        case .currentFile: return "Archivo actual"
        case .previewFile: return "Archivo de vista previa"
        case .startBatch: return "Iniciar lote"
        case .unlockPassword: return "Contraseña"
        case .passwordPlaceholder: return "Contraseña (para PDF protegido)"
        case .locked: return "El archivo actual está protegido"
        case .unlocked: return "El archivo actual no está protegido"
        case .batchPasswordHint: return "El modo lote usa una sola contraseña para todos los PDFs protegidos."
        case .sameAsInputFolder: return "Igual que la carpeta de entrada"
        case .dropPDFFiles: return "Suelta archivos PDF."
        case .noNewPDFFilesAdded: return "No se agregaron archivos PDF nuevos."
        case .filesAdded: return "Agregado(s): %d archivo(s)"
        case .removedFromBatch: return "Eliminado del lote: %@"
        case .removeFromBatchList: return "Quitar de la lista de lote"
        case .batchDoneWithRenamed: return "Lote finalizado: %d archivos (renombrados: %d)"
        case .background: return "Fondo"
        case .themeFrost: return "Escarcha"
        case .themeSky: return "Cielo"
        case .themeMint: return "Menta"
        case .themePeach: return "Melocotón"
        case .themeSand: return "Arena"
        }
    }
}

import SwiftUI

enum MacToolPage: String, CaseIterable, Identifiable {
    case markClean
    case unlock

    var id: String { rawValue }
}

struct ContentView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("macToolPage") private var selectedPageRaw: String = MacToolPage.markClean.rawValue

    private var localizer: Localizer {
        Localizer(language: AppLanguage(rawValue: appLanguageRaw) ?? .system)
    }

    private var selectedPageBinding: Binding<MacToolPage> {
        Binding(
            get: { MacToolPage(rawValue: selectedPageRaw) ?? .markClean },
            set: { selectedPageRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedPageBinding) {
            MarkCleanContentView()
                .tag(MacToolPage.markClean)
                .tabItem {
                    Text(localizer.t(.toolMarkClean))
                }

            PDFUnlockContentView()
                .tag(MacToolPage.unlock)
                .tabItem {
                    Text(localizer.t(.toolUnlock))
                }
        }
        .frame(minWidth: 1220, minHeight: 740)
    }
}

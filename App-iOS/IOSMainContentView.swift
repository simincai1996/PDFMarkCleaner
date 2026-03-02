import SwiftUI

enum IOSToolPage: String, CaseIterable, Identifiable {
    case markClean
    case unlock

    var id: String { rawValue }
}

struct IOSMainContentView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = IOSAppLanguage.system.rawValue
    @AppStorage("iosToolPage") private var selectedPageRaw: String = IOSToolPage.markClean.rawValue

    private var localizer: IOSLocalizer {
        IOSLocalizer(language: IOSAppLanguage(rawValue: appLanguageRaw) ?? .system)
    }

    private var selectedPageBinding: Binding<IOSToolPage> {
        Binding(
            get: { IOSToolPage(rawValue: selectedPageRaw) ?? .markClean },
            set: { selectedPageRaw = $0.rawValue }
        )
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        let content = Group {
            switch selectedPageBinding.wrappedValue {
            case .markClean:
                IOSContentView()
            case .unlock:
                IOSUnlockContentView()
            }
        }
        if isPad {
            content
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 8) {
                    HStack {
                        Spacer()
                        Picker("", selection: selectedPageBinding) {
                            Text(localizer.t(.toolMarkClean)).tag(IOSToolPage.markClean)
                            Text(localizer.t(.toolUnlock)).tag(IOSToolPage.unlock)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        )
                        .frame(maxWidth: 420)
                        Spacer()
                    }
                }
        }
    }
}

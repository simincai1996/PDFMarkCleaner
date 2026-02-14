import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    @AppStorage("backgroundTheme") private var backgroundThemeRaw: String = BackgroundTheme.frost.rawValue

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    private var localizer: Localizer {
        Localizer(language: AppLanguage(rawValue: appLanguageRaw) ?? .system)
    }

    private var themeBinding: Binding<BackgroundTheme> {
        Binding(
            get: { BackgroundTheme(rawValue: backgroundThemeRaw) ?? .frost },
            set: { backgroundThemeRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localizer.t(.settingsTitle))
                .font(.title2)
                .bold()

            LanguageMenu(
                title: localizer.t(.language),
                selection: languageBinding,
                options: [
                    (.system, localizer.t(.systemLanguage)),
                    (.english, localizer.t(.english)),
                    (.chineseSimplified, localizer.t(.chineseSimplified)),
                    (.chineseTraditional, localizer.t(.chineseTraditional)),
                    (.german, localizer.t(.german)),
                    (.spanish, localizer.t(.spanish))
                ]
            )

            ThemeMenu(
                title: localizer.t(.background),
                selection: themeBinding,
                options: [
                    (.frost, localizer.t(.themeFrost)),
                    (.sky, localizer.t(.themeSky)),
                    (.mint, localizer.t(.themeMint)),
                    (.peach, localizer.t(.themePeach)),
                    (.sand, localizer.t(.themeSand))
                ]
            )

            SettingsToggleRow(
                title: localizer.t(.advancedOptions),
                isOn: $enableAdvancedOptions
            )

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 220)
    }
}

private struct LanguageMenu: View {
    let title: String
    @Binding var selection: AppLanguage
    let options: [(AppLanguage, String)]
    private let menuWidth: CGFloat = 210
    private let labelWidth: CGFloat = 110
    private let rowWidth: CGFloat = 340

    private var selectedTitle: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .leading)
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(option.1) { selection = option.0 }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .frame(width: menuWidth, height: 28, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .frame(width: menuWidth, alignment: .leading)
            .layoutPriority(1)
        }
        .frame(maxWidth: rowWidth, alignment: .leading)
    }
}

private struct ThemeMenu: View {
    let title: String
    @Binding var selection: BackgroundTheme
    let options: [(BackgroundTheme, String)]
    private let menuWidth: CGFloat = 210
    private let labelWidth: CGFloat = 110
    private let rowWidth: CGFloat = 340

    private var selectedTitle: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .leading)
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button(option.1) { selection = option.0 }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .frame(width: menuWidth, height: 28, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .frame(width: menuWidth, alignment: .leading)
            .layoutPriority(1)
        }
        .frame(maxWidth: rowWidth, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    private let labelWidth: CGFloat = 110
    private let controlWidth: CGFloat = 210
    private let rowWidth: CGFloat = 340

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .leading)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: controlWidth, alignment: .leading)
        }
        .frame(maxWidth: rowWidth, alignment: .leading)
    }
}

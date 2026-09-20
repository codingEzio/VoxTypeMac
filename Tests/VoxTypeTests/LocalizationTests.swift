import Foundation
import Testing

@testable import VoxType

@Test func uiLanguagesCoverEverySupportedInterfaceLocale() {
  #expect(
    UILanguage.allCases.map(\.rawValue) == [
      "en", "zh-Hant", "zh-Hans", "ja", "ko", "es", "ru", "uk",
    ])
}

@Test func everyLocalizationCatalogHasExactlyTheDeclaredKeys() throws {
  let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let root = projectRoot.appendingPathComponent("Resources", isDirectory: true)
  let catalogs = try LocalizationCatalog.loadAll(from: root)
  let expectedKeys = Set(LocalizationKey.allCases.map(\.rawValue))

  #expect(Set(catalogs.keys) == Set(UILanguage.allCases))
  for language in UILanguage.allCases {
    let catalog = catalogs[language, default: [:]]
    #expect(Set(catalog.keys) == expectedKeys)
    for key in LocalizationKey.allCases {
      #expect(placeholders(in: catalog[key.rawValue, default: ""]) == placeholders(in: key.english))
    }
  }
}

@Test func pluralRulesCoverSupportedLanguageFamilies() {
  #expect(LocalizationPlural.category(for: 1, language: .english) == .one)
  #expect(LocalizationPlural.category(for: 2, language: .english) == .other)
  #expect(LocalizationPlural.category(for: 1, language: .russian) == .one)
  #expect(LocalizationPlural.category(for: 2, language: .russian) == .few)
  #expect(LocalizationPlural.category(for: 5, language: .russian) == .many)
  #expect(LocalizationPlural.category(for: 11, language: .ukrainian) == .many)
  #expect(LocalizationPlural.category(for: 21, language: .ukrainian) == .one)
  #expect(LocalizationPlural.category(for: 3, language: .japanese) == .other)
}

@Test func everyLocaleHasPermissionPurposeStrings() throws {
  let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let expected = Set([
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "NSHumanReadableCopyright",
  ])
  for language in UILanguage.allCases {
    let url = projectRoot
      .appendingPathComponent("Resources/\(language.rawValue).lproj/InfoPlist.strings")
    let data = try Data(contentsOf: url)
    let values = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
    )
    #expect(Set(values.keys) == expected)
    #expect(values.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
  }
}

@Test func localizedFormattingPreservesRuntimeValues() {
  let catalog: [String: String] = [
    LocalizationKey.statusReadyShortcut.rawValue: "準備就緒 · %@",
    LocalizationKey.statusTextDeliveredArchiveFailed.rawValue: "文字已送出 · 封存失敗：%@",
  ]
  #expect(
    LocalizationCatalog.format(
      .statusReadyShortcut,
      arguments: ["⌥."],
      catalog: catalog
    ) == "準備就緒 · ⌥."
  )
  #expect(
    LocalizationCatalog.format(
      .statusTextDeliveredArchiveFailed,
      arguments: ["磁碟已滿"],
      catalog: catalog
    ) == "文字已送出 · 封存失敗：磁碟已滿"
  )
}

private func placeholders(in value: String) -> [String] {
  value.matches(of: /%(?:@|lld)/).map { String($0.output) }.sorted()
}

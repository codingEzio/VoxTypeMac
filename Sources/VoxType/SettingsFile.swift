import Foundation

struct SettingsFile {
  static let rootURL: URL = {
    do {
      return try VoxTypeExternalData.portableStateRoot()
    } catch {
      fatalError("\(ProductIdentity.displayName) external-data.json is invalid: \(error)")
    }
  }()
  static let configURL = rootURL.appendingPathComponent("config/config.toml")
  static let recordingsURL = rootURL.appendingPathComponent("recordings", isDirectory: true)
  static let modelsURL = rootURL.appendingPathComponent("models", isDirectory: true)
  static let cacheURL = rootURL.appendingPathComponent("cache", isDirectory: true)
  static let stateURL = rootURL.appendingPathComponent("state", isDirectory: true)
  static let temporaryURL = rootURL.appendingPathComponent("temp", isDirectory: true)

  static func requireContained(_ url: URL) throws {
    let root = rootURL.standardizedFileURL
    let candidate = url.standardizedFileURL
    guard candidate.path.hasPrefix(root.path + "/"),
          !VoxTypeExternalData.containsSymbolicLink(from: root, through: candidate)
    else {
      throw CocoaError(.fileWriteNoPermission)
    }
  }

  private(set) var values: [String: String] = [:]

  init(url: URL = SettingsFile.configURL) {
    guard let source = try? String(contentsOf: url, encoding: .utf8) else { return }
    for rawLine in source.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
        continue
      }
      let key = line[..<separator].trimmingCharacters(in: .whitespaces)
      let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      values[key] = Self.decode(rawValue)
    }
  }

  subscript(key: String) -> String? { values[key] }

  mutating func set(_ value: String, for key: String) {
    values[key] = value
  }

  func write(to url: URL = SettingsFile.configURL) throws {
    try Self.requireContained(url)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let orderedKeys = [
      "schema_version", "ui_language", "speech_mode", "delivery_mode",
      "preserve_clipboard",
      "show_floating_hud", "launch_at_login", "dictation_shortcut",
      "paste_delay_milliseconds", "motion_style",
    ]
    let booleanKeys: Set<String> = [
      "preserve_clipboard", "show_floating_hud", "launch_at_login",
    ]
    let integerKeys: Set<String> = [
      "schema_version", "paste_delay_milliseconds",
    ]
    let body = orderedKeys.compactMap { key -> String? in
      guard let value = values[key] else { return nil }
      if booleanKeys.contains(key) || integerKeys.contains(key) {
        return "\(key) = \(value)"
      }
      return "\(key) = \"\(Self.encode(value))\""
    }.joined(separator: "\n")
    let content = "# \(ProductIdentity.displayName) portable user configuration\n\(body)\n"
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  private static func decode(_ value: String) -> String {
    guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
    return String(value.dropFirst().dropLast())
      .replacingOccurrences(of: "\\\"", with: "\"")
      .replacingOccurrences(of: "\\\\", with: "\\")
  }

  private static func encode(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}

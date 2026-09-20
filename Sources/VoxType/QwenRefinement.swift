import Foundation

enum RefinementBackend: String, Sendable {
  case qwen3
  case senseVoice

  var title: String {
    switch self {
    case .qwen3: "Qwen3-ASR 1.7B · MLX"
    case .senseVoice: "SenseVoice · 261 MB"
    }
  }
}

struct QwenRefinementConfiguration: Decodable, Equatable, Sendable {
  struct Artifact: Decodable, Equatable, Sendable {
    let name: String
    let size: Int64
    let sha256: String?
    let gitBlob: String
  }
  let repository: String
  let revision: String
  let runtimePackage: String
  let timeoutSeconds: Double
  let files: [Artifact]
}

enum QwenRefinement {
  static var modelURL: URL { SettingsFile.modelsURL.appendingPathComponent("qwen3-asr") }
  static var pythonURL: URL {
    SettingsFile.modelsURL.appendingPathComponent("qwen3-asr-venv/bin/python")
  }
  static var configurationURL: URL {
    Bundle.main.url(forResource: "qwen-asr", withExtension: "json")
      ?? SettingsFile.rootURL.deletingLastPathComponent().appendingPathComponent(
        "config/qwen-asr.json")
  }
  static var helperURL: URL {
    Bundle.main.url(forResource: "qwen_refine", withExtension: "py")
      ?? SettingsFile.rootURL.deletingLastPathComponent().appendingPathComponent(
        "script/qwen_refine.py")
  }
  static func configuration() throws -> QwenRefinementConfiguration {
    try JSONDecoder().decode(
      QwenRefinementConfiguration.self, from: Data(contentsOf: configurationURL))
  }
  static var isReady: Bool {
    guard FileManager.default.isExecutableFile(atPath: pythonURL.path),
      FileManager.default.fileExists(atPath: helperURL.path),
      let config = try? configuration(),
      let receipt = try? Data(contentsOf: modelURL.appendingPathComponent("verified.json")),
      let verified = try? JSONDecoder().decode(QwenRefinementConfiguration.self, from: receipt),
      config == verified, !config.files.isEmpty
    else { return false }
    return config.files.allSatisfy { artifact in
      let url = modelURL.appendingPathComponent(artifact.name)
      guard artifact.name == url.lastPathComponent,
        (try? SettingsFile.requireContained(url)) != nil,
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
      else { return false }
      return Int64(values.fileSize ?? -1) == artifact.size
    }
  }
}

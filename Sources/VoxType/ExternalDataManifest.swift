import Darwin
import Foundation

enum ExternalDataRoutingError: Error, CustomStringConvertible {
  case invalid(String)

  var description: String {
    switch self {
    case .invalid(let message): message
    }
  }
}

private struct ExternalDataManifest: Decodable {
  let schemaVersion: Int
  let projectId: String
  let sources: [ExternalDataSource]
}

private struct ExternalDataSource: Decodable {
  let id: String
  let description: String
  let kind: String
  let access: String
  let root: String
  let path: String
  let required: Bool
  let sensitive: Bool
  let overrideEnv: String
}

enum VoxTypeExternalData {
  private static let manifestName = "external-data"
  private static let projectId = "client-voxtype"
  private static let sourceId = "portable-state-root"

  static func portableStateRoot(
    manifestURL: URL? = nil,
    applicationSupportRoot: URL? = nil
  ) throws -> URL {
    let location = try manifestURL ?? defaultManifestURL()
    let data = try Data(contentsOf: location)
    let manifest = try JSONDecoder().decode(ExternalDataManifest.self, from: data)
    guard manifest.schemaVersion == 1, manifest.projectId == projectId else {
      throw ExternalDataRoutingError.invalid(
        "external-data.json schema or project owner differs"
      )
    }
    guard let source = manifest.sources.first(where: { $0.id == sourceId }) else {
      throw ExternalDataRoutingError.invalid(
        "external-data.json does not declare \(sourceId)"
      )
    }
    guard manifest.sources.filter({ $0.id == sourceId }).count == 1 else {
      throw ExternalDataRoutingError.invalid(
        "external-data.json declares \(sourceId) more than once"
      )
    }
    try validate(source)

    let root = try (applicationSupportRoot ?? defaultApplicationSupportRoot())
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let declaredCandidate =
      root
      .appendingPathComponent(source.path, isDirectory: true)
      .standardizedFileURL
    guard !containsSymbolicLink(from: root, through: declaredCandidate) else {
      throw ExternalDataRoutingError.invalid(
        "app data must be a real directory inside Application Support"
      )
    }
    let candidate = declaredCandidate.resolvingSymlinksInPath()
    guard candidate.path.hasPrefix(root.path + "/") else {
      throw ExternalDataRoutingError.invalid(
        "app data resolves outside Application Support"
      )
    }
    return candidate
  }

  private static func defaultApplicationSupportRoot() throws -> URL {
    try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
  }

  private static func defaultManifestURL() throws -> URL {
    if let bundled = Bundle.main.url(
      forResource: manifestName,
      withExtension: "json"
    ) {
      return bundled
    }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
      .standardizedFileURL
      .deletingLastPathComponent()
    for start in [URL(fileURLWithPath: FileManager.default.currentDirectoryPath), executable] {
      if let root = sourceRoot(containing: start) {
        return root.appendingPathComponent("external-data.json")
      }
    }
    throw ExternalDataRoutingError.invalid("external-data.json cannot be located")
  }

  private static func sourceRoot(containing start: URL) -> URL? {
    var candidate = start.standardizedFileURL
    while true {
      if isSourceRoot(candidate) { return candidate }
      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path { return nil }
      candidate = parent
    }
  }

  private static func isSourceRoot(_ url: URL) -> Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
      && fm.fileExists(atPath: url.appendingPathComponent("external-data.json").path)
      && fm.fileExists(atPath: url.appendingPathComponent("config/product.conf").path)
  }

  static func containsSymbolicLink(from root: URL, through candidate: URL) -> Bool {
    let rootPath = root.standardizedFileURL.path
    let candidatePath = candidate.standardizedFileURL.path
    guard candidatePath.hasPrefix(rootPath + "/") else { return true }

    let relativePath = candidatePath.dropFirst(rootPath.count + 1)
    var current = root.standardizedFileURL
    for component in relativePath.split(separator: "/") {
      current.appendPathComponent(String(component))
      var information = stat()
      let result = current.path.withCString { lstat($0, &information) }
      if result != 0 {
        return errno != ENOENT
      }
      if information.st_mode & S_IFMT == S_IFLNK {
        return true
      }
    }
    return false
  }

  private static func validate(_ source: ExternalDataSource) throws {
    let parts = source.path.split(separator: "/", omittingEmptySubsequences: false)
    guard
      source.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        == false,
      source.kind == "directory",
      source.access == "read-write",
      source.root == "application-support",
      source.required,
      source.sensitive,
      source.overrideEnv.isEmpty,
      source.path == "VoxTypeMac",
      source.path.hasPrefix("/") == false,
      parts.isEmpty == false,
      parts.allSatisfy({ $0.isEmpty == false && $0 != ".." })
    else {
      throw ExternalDataRoutingError.invalid(
        "\(sourceId) contract differs from the \(ProductIdentity.displayName) Application Support directory"
      )
    }
  }
}

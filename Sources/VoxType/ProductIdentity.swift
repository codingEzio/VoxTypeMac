import Foundation

enum ProductIdentity {
  static var displayName: String {
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
      !name.isEmpty
    {
      return name
    }
    return ProcessInfo.processInfo.processName
  }
}

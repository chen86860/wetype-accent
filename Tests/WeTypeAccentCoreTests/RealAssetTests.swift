import Foundation
import Testing

@testable import WeTypeAccentCore

@Test func patchesRealAssetCatalogWhenFixtureIsProvided() throws {
  guard let path = ProcessInfo.processInfo.environment["WETYPE_ORIGINAL_ASSETS_FIXTURE"] else {
    return
  }
  let sourceURL = URL(fileURLWithPath: path)
  let source = try Data(contentsOf: sourceURL)
  #expect(AssetPatcher.sha256(source) == WeTypeProfile.version220Build617.originalAssetsSHA256)

  let palette = AccentPalette(
    light: try RGBColor(hex: "#007AFF"),
    dark: try RGBColor(hex: "#0A84FF"),
    secondary: try RGBColor(hex: "#409CFF"),
    background: try RGBColor(hex: "#E8F2FF")
  )
  let patched = try AssetPatcher.patch(data: source, palette: palette)
  let destination = FileManager.default.temporaryDirectory
    .appendingPathComponent("wetype-accent-real-\(UUID().uuidString).car")
  try patched.write(to: destination)
  defer { try? FileManager.default.removeItem(at: destination) }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  process.arguments = ["assetutil", "--validate-file", destination.path]
  try process.run()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)
}

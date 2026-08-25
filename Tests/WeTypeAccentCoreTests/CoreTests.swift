import Foundation
import Testing

@testable import WeTypeAccentCore

@Test func parsesHexColors() throws {
  let color = try RGBColor(hex: "#0A84FF")
  #expect(color == RGBColor(red: 10, green: 132, blue: 255))
  #expect(color.hex == "#0A84FF")
}

@Test func rejectsInvalidColors() {
  #expect(throws: AccentError.invalidColor("blue")) {
    try RGBColor(hex: "blue")
  }
}

@Test func derivesPalette() throws {
  let palette = AccentPalette(light: try RGBColor(hex: "#007AFF"))
  #expect(palette.light.hex == "#007AFF")
  #expect(palette.dark.hex == "#1485FF")
  #expect(palette.secondary.hex == "#409BFF")
  #expect(palette.background.hex == "#E6F2FF")
}

@Test func patchesExpectedSerializedRecords() throws {
  let palette = AccentPalette(light: try RGBColor(hex: "#007AFF"))
  var fixture = Data("fixture".utf8)
  for record in AssetPatcher.records(for: palette) {
    let source = serialized(record.source)
    for _ in 0..<record.expectedOccurrences {
      fixture.append(source)
      fixture.append(Data([0xde, 0xad, 0xbe, 0xef]))
    }
  }

  let patched = try AssetPatcher.patch(data: fixture, palette: palette)
  #expect(patched.count == fixture.count)
  #expect(patched != fixture)
}

@Test func refusesUnexpectedRecordCounts() throws {
  let palette = AccentPalette(light: try RGBColor(hex: "#007AFF"))
  #expect(throws: AccentError.self) {
    try AssetPatcher.patch(data: Data(), palette: palette)
  }
}

@Test func acceptsSupportedWeTypeVersions() {
  #expect(WeTypeCompatibility.supports("2.2.0"))
  #expect(WeTypeCompatibility.supports("2.2"))
  #expect(WeTypeCompatibility.supports("2.2.1"))
  #expect(WeTypeCompatibility.supports("2.10.0"))
  #expect(WeTypeCompatibility.supports("3.0.0"))
}

@Test func rejectsOldOrMalformedWeTypeVersions() {
  #expect(!WeTypeCompatibility.supports("2.1.99"))
  #expect(!WeTypeCompatibility.supports("1.99.99"))
  #expect(!WeTypeCompatibility.supports("2.2.0-beta"))
  #expect(!WeTypeCompatibility.supports("not-a-version"))
}

private func serialized(_ rgba: [UInt8]) -> Data {
  var result = Data()
  for component in rgba {
    var bits = (Double(component) / 255.0).bitPattern.littleEndian
    withUnsafeBytes(of: &bits) { result.append(contentsOf: $0) }
  }
  return result
}

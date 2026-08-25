import CryptoKit
import Foundation

public struct RGBColor: Equatable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(hex: String) throws {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6, let number = UInt32(value, radix: 16) else {
      throw AccentError.invalidColor(hex)
    }
    self.init(
      red: UInt8((number >> 16) & 0xff),
      green: UInt8((number >> 8) & 0xff),
      blue: UInt8(number & 0xff)
    )
  }

  public var hex: String {
    String(format: "#%02X%02X%02X", red, green, blue)
  }

  public func mixed(with other: RGBColor, amount: Double) -> RGBColor {
    let ratio = max(0, min(1, amount))
    func channel(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
      UInt8((Double(lhs) * (1 - ratio) + Double(rhs) * ratio).rounded())
    }
    return RGBColor(
      red: channel(red, other.red),
      green: channel(green, other.green),
      blue: channel(blue, other.blue)
    )
  }
}

public struct AccentPalette: Equatable, Sendable {
  public let light: RGBColor
  public let dark: RGBColor
  public let secondary: RGBColor
  public let background: RGBColor

  public init(
    light: RGBColor,
    dark: RGBColor? = nil,
    secondary: RGBColor? = nil,
    background: RGBColor? = nil
  ) {
    let white = RGBColor(red: 255, green: 255, blue: 255)
    self.light = light
    self.dark = dark ?? light.mixed(with: white, amount: 0.08)
    self.secondary = secondary ?? light.mixed(with: white, amount: 0.25)
    self.background = background ?? light.mixed(with: white, amount: 0.90)
  }
}

public enum AccentError: LocalizedError, Equatable {
  case invalidColor(String)
  case unsupportedVersion(version: String, build: String)
  case assetHashMismatch(expected: String, actual: String)
  case patchRecordMismatch(name: String, expected: Int, actual: Int)
  case commandFailed(command: String, output: String)
  case invalidApplication(String)
  case administratorRequired
  case backupMissing(String)
  case runtimeVerificationFailed

  public var errorDescription: String? {
    switch self {
    case .invalidColor(let value):
      return "无效颜色“\(value)”，请使用 #RRGGBB 格式。"
    case .unsupportedVersion(let version, let build):
      return "当前微信输入法 \(version)（\(build)）低于最低支持版本 2.2.0，或版本号无法识别。没有修改任何文件。"
    case .assetHashMismatch(let expected, let actual):
      return "资源哈希不匹配。预期 \(expected)，实际 \(actual)。文件可能已被修改。"
    case .patchRecordMismatch(let name, let expected, let actual):
      return "颜色记录 \(name) 数量异常：预期 \(expected)，实际 \(actual)。"
    case .commandFailed(let command, let output):
      return "命令执行失败：\(command)\n\(output)"
    case .invalidApplication(let path):
      return "不是受支持的微信输入法：\(path)"
    case .administratorRequired:
      return "写入 /Library/Input Methods 需要管理员权限，请在命令前加 sudo。"
    case .backupMissing(let path):
      return "找不到原版备份：\(path)"
    case .runtimeVerificationFailed:
      return "补丁写入后微信输入法没有成功重新启动，已尝试恢复原版。"
    }
  }
}

public struct WeTypeProfile: Sendable {
  public let shortVersion: String
  public let build: String
  public let originalAssetsSHA256: String

  public static let version220Build617 = WeTypeProfile(
    shortVersion: "2.2.0",
    build: "617",
    originalAssetsSHA256: "b4d474f0b9133fc314d1a12bee4cff2ce2e4a9563dcc6b2f4856b7ca26816a3b"
  )
}

public enum WeTypeCompatibility {
  public static let minimumVersion = "2.2.0"

  public static func supports(_ version: String) -> Bool {
    guard let candidate = components(of: version), let minimum = components(of: minimumVersion)
    else { return false }
    let count = max(candidate.count, minimum.count)
    for index in 0..<count {
      let lhs = index < candidate.count ? candidate[index] : 0
      let rhs = index < minimum.count ? minimum[index] : 0
      if lhs != rhs { return lhs > rhs }
    }
    return true
  }

  private static func components(of version: String) -> [Int]? {
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    guard !parts.isEmpty else { return nil }
    let values = parts.compactMap { part -> Int? in
      guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return nil }
      return Int(part)
    }
    return values.count == parts.count ? values : nil
  }
}

public struct PatchRecord: Sendable {
  public let name: String
  public let source: [UInt8]
  public let target: [UInt8]
  public let expectedOccurrences: Int
}

public enum AssetPatcher {
  public static func records(for palette: AccentPalette) -> [PatchRecord] {
    [
      PatchRecord(
        name: "bc16 light/universal", source: [22, 172, 102, 255], target: rgba(palette.light),
        expectedOccurrences: 2),
      PatchRecord(
        name: "bc16 dark", source: [0, 212, 142, 255], target: rgba(palette.dark),
        expectedOccurrences: 1),
      PatchRecord(
        name: "bg02 light/universal", source: [232, 247, 240, 255],
        target: rgba(palette.background), expectedOccurrences: 2),
      PatchRecord(
        name: "bg03 light/universal", source: [0, 177, 118, 255], target: rgba(palette.light),
        expectedOccurrences: 2),
      PatchRecord(
        name: "bg03 dark", source: [0, 168, 111, 255], target: rgba(palette.dark),
        expectedOccurrences: 1),
      PatchRecord(
        name: "bg04 all appearances", source: [35, 200, 145, 255], target: rgba(palette.secondary),
        expectedOccurrences: 3),
    ]
  }

  public static func patch(data: Data, palette: AccentPalette) throws -> Data {
    var output = data
    for record in records(for: palette) {
      let source = serializedRGBA(record.source)
      let target = serializedRGBA(record.target)
      let occurrences = ranges(of: source, in: output)
      guard occurrences.count == record.expectedOccurrences else {
        throw AccentError.patchRecordMismatch(
          name: record.name,
          expected: record.expectedOccurrences,
          actual: occurrences.count
        )
      }
      for range in occurrences.reversed() {
        output.replaceSubrange(range, with: target)
      }
    }
    return output
  }

  public static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func rgba(_ color: RGBColor) -> [UInt8] {
    [color.red, color.green, color.blue, 255]
  }

  private static func serializedRGBA(_ rgba: [UInt8]) -> Data {
    var data = Data()
    for component in rgba {
      var littleEndian = (Double(component) / 255.0).bitPattern.littleEndian
      withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    return data
  }

  private static func ranges(of needle: Data, in haystack: Data) -> [Range<Data.Index>] {
    guard !needle.isEmpty else { return [] }
    var result: [Range<Data.Index>] = []
    var searchStart = haystack.startIndex
    while searchStart < haystack.endIndex,
      let range = haystack.range(of: needle, in: searchStart..<haystack.endIndex)
    {
      result.append(range)
      searchStart = range.upperBound
    }
    return result
  }
}

public struct AppMetadata: Sendable {
  public let bundleIdentifier: String
  public let shortVersion: String
  public let build: String

  public static func load(from appURL: URL) throws -> AppMetadata {
    let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
    let data = try Data(contentsOf: plistURL)
    guard
      let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let identifier = plist["CFBundleIdentifier"] as? String,
      let version = plist["CFBundleShortVersionString"] as? String,
      let build = plist["CFBundleVersion"] as? String,
      identifier == "com.tencent.inputmethod.wetype"
    else {
      throw AccentError.invalidApplication(appURL.path)
    }
    return AppMetadata(bundleIdentifier: identifier, shortVersion: version, build: build)
  }
}

import Darwin
import Foundation
import WeTypeAccentCore

private let defaultAppPath = "/Library/Input Methods/WeType.app"
private let supportPath = "/Library/Application Support/WeTypeAccent"
private let statePath = supportPath + "/state.json"
private let profile = WeTypeProfile.version220Build617

private struct PatchState: Codable {
  let appPath: String
  let version: String
  let build: String
  let originalAssetsSHA256: String
  let patchedAssetsSHA256: String
  let backupPath: String
  let light: String
  let dark: String
  let secondary: String
  let background: String
  let appliedAt: Date
}

private struct Arguments {
  var command = "help"
  var appPath = defaultAppPath
  var color: String?
  var dark: String?
  var secondary: String?
  var background: String?
  var yes = false

  init(_ values: [String]) throws {
    if values.count > 1 { command = values[1] }
    var index = 2
    while index < values.count {
      let value = values[index]
      switch value {
      case "--app":
        index += 1
        appPath = try requireValue(values, index, option: value)
      case "--color":
        index += 1
        color = try requireValue(values, index, option: value)
      case "--dark":
        index += 1
        dark = try requireValue(values, index, option: value)
      case "--secondary":
        index += 1
        secondary = try requireValue(values, index, option: value)
      case "--background":
        index += 1
        background = try requireValue(values, index, option: value)
      case "--yes", "-y": yes = true
      default:
        if !value.hasPrefix("-") && color == nil {
          color = value
        } else {
          throw AccentError.invalidApplication("未知参数：\(value)")
        }
      }
      index += 1
    }
  }

  private func requireValue(_ values: [String], _ index: Int, option: String) throws -> String {
    guard index < values.count else { throw AccentError.invalidApplication("\(option) 缺少参数") }
    return values[index]
  }
}

@discardableResult
private func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws
  -> String
{
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  let output = String(decoding: outputData, as: UTF8.self)
  if process.terminationStatus != 0 && !allowFailure {
    throw AccentError.commandFailed(
      command: ([executable] + arguments).joined(separator: " "), output: output)
  }
  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func palette(from args: Arguments) throws -> AccentPalette {
  guard let color = args.color else { throw AccentError.invalidColor("缺少 --color") }
  return AccentPalette(
    light: try RGBColor(hex: color),
    dark: try args.dark.map(RGBColor.init(hex:)),
    secondary: try args.secondary.map(RGBColor.init(hex:)),
    background: try args.background.map(RGBColor.init(hex:))
  )
}

private func printPalette(_ palette: AccentPalette) {
  print("浅色重点色：\(palette.light.hex)")
  print("深色重点色：\(palette.dark.hex)")
  print("次级重点色：\(palette.secondary.hex)")
  print("淡色背景：  \(palette.background.hex)")
}

private func loadState() -> PatchState? {
  guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)) else { return nil }
  return try? JSONDecoder().decode(PatchState.self, from: data)
}

private func writeState(_ state: PatchState) throws {
  try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: supportPath),
    withIntermediateDirectories: true
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(state).write(to: URL(fileURLWithPath: statePath), options: .atomic)
}

private func assetsURL(for appURL: URL) -> URL {
  appURL.appendingPathComponent("Contents/Resources/Assets.car")
}

private func validateVersion(_ metadata: AppMetadata) throws {
  guard metadata.shortVersion == profile.shortVersion, metadata.build == profile.build else {
    throw AccentError.unsupportedVersion(version: metadata.shortVersion, build: metadata.build)
  }
}

private func requireAdministrator() throws {
  guard geteuid() == 0 else { throw AccentError.administratorRequired }
}

private func confirm(_ prompt: String, yes: Bool) -> Bool {
  if yes { return true }
  print(prompt + " [y/N] ", terminator: "")
  return readLine()?.lowercased() == "y"
}

private func isRunning(pid: String) -> Bool {
  guard let numericPID = Int32(pid) else { return false }
  return Darwin.kill(numericPID, 0) == 0
}

private func waitForExit(pid: String) {
  for _ in 0..<20 {
    if !isRunning(pid: pid) { break }
    usleep(250_000)
  }
}

private func targetUserID() -> uid_t {
  if let value = ProcessInfo.processInfo.environment["SUDO_UID"], let uid = uid_t(value) {
    return uid
  }
  return getuid()
}

private func weTypePIDs(userID: uid_t, appPath: String) throws -> Set<String> {
  let executable = URL(fileURLWithPath: appPath).standardizedFileURL
    .appendingPathComponent("Contents/MacOS/WeType").path
  let output = try run("/bin/ps", ["-axo", "uid=,pid=,command="], allowFailure: true)
  return Set(
    output.split(separator: "\n").compactMap { line in
      let fields = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
      guard fields.count == 3, fields[0] == Substring(String(userID)),
        fields[2] == Substring(executable)
      else { return nil }
      return String(fields[1])
    })
}

private func restartWeType(appPath: String) throws {
  let userID = targetUserID()
  let oldPIDs = try weTypePIDs(userID: userID, appPath: appPath)
  for pid in oldPIDs {
    _ = try run("/bin/kill", [pid], allowFailure: true)
    waitForExit(pid: pid)
    if isRunning(pid: pid) {
      _ = try run("/bin/kill", ["-9", pid], allowFailure: true)
      waitForExit(pid: pid)
    }
  }
  if geteuid() == 0 && userID != 0 {
    _ = try run(
      "/bin/launchctl",
      ["asuser", String(userID), "/usr/bin/sudo", "-u", "#\(userID)", "/usr/bin/open", appPath]
    )
  } else {
    _ = try run("/usr/bin/open", [appPath])
  }
  for _ in 0..<20 {
    let newPIDs = try weTypePIDs(userID: userID, appPath: appPath).subtracting(oldPIDs)
    if !newPIDs.isEmpty { return }
    usleep(250_000)
  }
  throw AccentError.runtimeVerificationFailed
}

private func backupURL(metadata: AppMetadata) -> URL {
  URL(fileURLWithPath: supportPath)
    .appendingPathComponent("Backups")
    .appendingPathComponent(
      "\(metadata.shortVersion)-\(metadata.build)-\(profile.originalAssetsSHA256.prefix(12))"
    )
    .appendingPathComponent("WeType.app")
}

private func validateBackup(_ backup: URL, metadata: AppMetadata) throws {
  let backupMetadata = try AppMetadata.load(from: backup)
  guard
    backupMetadata.shortVersion == metadata.shortVersion,
    backupMetadata.build == metadata.build
  else {
    throw AccentError.invalidApplication(backup.path)
  }
  let hash = AssetPatcher.sha256(try Data(contentsOf: assetsURL(for: backup)))
  guard hash == profile.originalAssetsSHA256 else {
    throw AccentError.assetHashMismatch(expected: profile.originalAssetsSHA256, actual: hash)
  }
  _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", backup.path])
}

private func ensureBackup(appURL: URL, metadata: AppMetadata, sourceHash: String) throws -> URL {
  let destination = backupURL(metadata: metadata)
  if FileManager.default.fileExists(atPath: destination.path) {
    try validateBackup(destination, metadata: metadata)
    return destination
  }
  guard sourceHash == profile.originalAssetsSHA256 else {
    throw AccentError.assetHashMismatch(expected: profile.originalAssetsSHA256, actual: sourceHash)
  }
  try FileManager.default.createDirectory(
    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
  let temporary = destination.deletingLastPathComponent()
    .appendingPathComponent(".WeType.app.\(UUID().uuidString).tmp")
  defer { try? FileManager.default.removeItem(at: temporary) }
  _ = try run("/usr/bin/ditto", ["--noextattr", "--noqtn", appURL.path, temporary.path])
  try validateBackup(temporary, metadata: metadata)
  try FileManager.default.moveItem(at: temporary, to: destination)
  return destination
}

private func restoreBackup(_ backupURL: URL, to appURL: URL, removeState: Bool) throws {
  guard FileManager.default.fileExists(atPath: backupURL.path) else {
    throw AccentError.backupMissing(backupURL.path)
  }
  _ = try run("/usr/bin/ditto", ["--noextattr", "--noqtn", backupURL.path, appURL.path])
  _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
  let restoredHash = AssetPatcher.sha256(try Data(contentsOf: assetsURL(for: appURL)))
  guard restoredHash == profile.originalAssetsSHA256 else {
    throw AccentError.assetHashMismatch(
      expected: profile.originalAssetsSHA256, actual: restoredHash)
  }
  try restartWeType(appPath: appURL.path)
  if removeState { try? FileManager.default.removeItem(atPath: statePath) }
}

private func apply(args: Arguments) throws {
  try requireAdministrator()
  let appURL = URL(fileURLWithPath: args.appPath)
  let metadata = try AppMetadata.load(from: appURL)
  try validateVersion(metadata)
  let selectedPalette = try palette(from: args)
  printPalette(selectedPalette)
  guard confirm("这会备份并重新签名微信输入法，继续吗？", yes: args.yes) else {
    print("已取消，没有修改任何文件。")
    return
  }

  let liveAssets = try Data(contentsOf: assetsURL(for: appURL))
  let liveHash = AssetPatcher.sha256(liveAssets)
  let backup = try ensureBackup(appURL: appURL, metadata: metadata, sourceHash: liveHash)
  let originalAssetsURL = assetsURL(for: backup)
  let originalAssets = try Data(contentsOf: originalAssetsURL)
  let originalHash = AssetPatcher.sha256(originalAssets)
  guard originalHash == profile.originalAssetsSHA256 else {
    throw AccentError.assetHashMismatch(
      expected: profile.originalAssetsSHA256, actual: originalHash)
  }

  let patched = try AssetPatcher.patch(data: originalAssets, palette: selectedPalette)
  let state = PatchState(
    appPath: appURL.standardizedFileURL.path,
    version: metadata.shortVersion,
    build: metadata.build,
    originalAssetsSHA256: originalHash,
    patchedAssetsSHA256: AssetPatcher.sha256(patched),
    backupPath: backup.path,
    light: selectedPalette.light.hex,
    dark: selectedPalette.dark.hex,
    secondary: selectedPalette.secondary.hex,
    background: selectedPalette.background.hex,
    appliedAt: Date()
  )
  let temporaryURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("wetype-accent-\(UUID().uuidString).car")
  try patched.write(to: temporaryURL, options: .atomic)
  defer { try? FileManager.default.removeItem(at: temporaryURL) }
  _ = try run("/usr/bin/xcrun", ["assetutil", "--validate-file", temporaryURL.path])

  do {
    try patched.write(to: assetsURL(for: appURL), options: .atomic)
    _ = try run(
      "/usr/bin/codesign",
      [
        "--force", "--deep", "--sign", "-",
        "--preserve-metadata=identifier,entitlements",
        appURL.path,
      ])
    _ = try run(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
    try writeState(state)
    try restartWeType(appPath: appURL.path)
  } catch {
    try? restoreBackup(backup, to: appURL, removeState: false)
    try? FileManager.default.removeItem(atPath: statePath)
    throw error
  }
  print("补丁已应用，微信输入法已重新启动。")
}

private func restore(args: Arguments) throws {
  try requireAdministrator()
  let appURL = URL(fileURLWithPath: args.appPath)
  let metadata = try AppMetadata.load(from: appURL)
  try validateVersion(metadata)
  guard let state = loadState() else { throw AccentError.backupMissing(statePath) }
  guard state.appPath == appURL.standardizedFileURL.path else {
    throw AccentError.invalidApplication("状态记录属于另一份微信输入法：\(state.appPath)")
  }
  guard confirm("将恢复腾讯原版微信输入法，继续吗？", yes: args.yes) else {
    print("已取消。")
    return
  }
  try restoreBackup(URL(fileURLWithPath: state.backupPath), to: appURL, removeState: true)
  print("腾讯原版已恢复并重新启动。")
}

private func status(args: Arguments) throws {
  let appURL = URL(fileURLWithPath: args.appPath)
  let metadata = try AppMetadata.load(from: appURL)
  let assets = try Data(contentsOf: assetsURL(for: appURL))
  let hash = AssetPatcher.sha256(assets)
  print("微信输入法：\(metadata.shortVersion)（\(metadata.build)）")
  print("资源 SHA-256：\(hash)")
  if hash == profile.originalAssetsSHA256 {
    print("状态：腾讯原版资源")
  } else if let state = loadState(), state.appPath == appURL.standardizedFileURL.path,
    hash == state.patchedAssetsSHA256
  {
    print("状态：已由 WeType Accent 修改")
    print("颜色：\(state.light) / \(state.dark)")
    print("备份：\(state.backupPath)")
  } else {
    print("状态：未知或由其他工具修改")
  }
  let pids = try weTypePIDs(userID: targetUserID(), appPath: appURL.path)
  print(pids.isEmpty ? "进程：当前用户未运行" : "进程：当前用户运行中（PID \(pids.sorted().first!)）")
}

private func doctor(args: Arguments) throws {
  let appURL = URL(fileURLWithPath: args.appPath)
  _ = try AppMetadata.load(from: appURL)
  _ = try run("/usr/bin/xcrun", ["assetutil", "--validate-file", assetsURL(for: appURL).path])
  _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
  try status(args: args)
  print("诊断：资源和代码签名验证通过。")
}

private func help() {
  print(
    """
    WeType Accent — 自定义 macOS 微信输入法候选窗重点色

    用法：
      wetype-accent preview --color '#007AFF'
      sudo wetype-accent apply --color '#007AFF' [--dark '#0A84FF'] [--yes]
      wetype-accent status
      sudo wetype-accent restore [--yes]
      wetype-accent doctor

    高级颜色参数：--secondary '#409CFF' --background '#E8F2FF'
    当前支持：微信输入法 2.2.0（617）
    """)
}

do {
  let args = try Arguments(CommandLine.arguments)
  switch args.command {
  case "preview": printPalette(try palette(from: args))
  case "apply": try apply(args: args)
  case "restore": try restore(args: args)
  case "status": try status(args: args)
  case "doctor": try doctor(args: args)
  case "help", "--help", "-h": help()
  case "version", "--version": print("wetype-accent 0.1.0")
  default:
    help()
    exit(2)
  }
} catch {
  fputs("错误：\(error.localizedDescription)\n", stderr)
  exit(1)
}

#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import readline from "node:readline/promises";
import { fileURLToPath } from "node:url";

const VERSION = "0.2.0";
const MINIMUM_WETYPE_VERSION = "2.2.0";
const DEFAULT_APP_PATH = "/Library/Input Methods/WeType.app";
const SUPPORT_PATH = "/Library/Application Support/WeTypeAccent";
const STATE_PATH = path.join(SUPPORT_PATH, "state.json");
const KNOWN_220_ASSETS_SHA256 =
  "b4d474f0b9133fc314d1a12bee4cff2ce2e4a9563dcc6b2f4856b7ca26816a3b";

class AccentError extends Error {}

export function parseHex(value) {
  const normalized = value.trim().replace(/^#/, "");
  if (!/^[0-9a-fA-F]{6}$/.test(normalized)) {
    throw new AccentError(`无效颜色“${value}”，请使用 #RRGGBB 格式。`);
  }
  return {
    red: Number.parseInt(normalized.slice(0, 2), 16),
    green: Number.parseInt(normalized.slice(2, 4), 16),
    blue: Number.parseInt(normalized.slice(4, 6), 16),
  };
}

export function colorHex(color) {
  return `#${[color.red, color.green, color.blue]
    .map((component) => component.toString(16).padStart(2, "0"))
    .join("")}`.toUpperCase();
}

function mixWithWhite(color, amount) {
  const mix = (channel) => Math.round(channel * (1 - amount) + 255 * amount);
  return { red: mix(color.red), green: mix(color.green), blue: mix(color.blue) };
}

export function derivePalette({ color, dark, secondary, background }) {
  const lightColor = parseHex(color);
  return {
    light: lightColor,
    dark: dark ? parseHex(dark) : mixWithWhite(lightColor, 0.08),
    secondary: secondary ? parseHex(secondary) : mixWithWhite(lightColor, 0.25),
    background: background ? parseHex(background) : mixWithWhite(lightColor, 0.9),
  };
}

function versionComponents(version) {
  const parts = version.split(".");
  if (parts.length === 0 || parts.some((part) => !/^\d+$/.test(part))) return null;
  const values = parts.map(Number);
  return values.every(Number.isSafeInteger) ? values : null;
}

export function supportsVersion(version) {
  const candidate = versionComponents(version);
  const minimum = versionComponents(MINIMUM_WETYPE_VERSION);
  if (!candidate || !minimum) return false;
  const count = Math.max(candidate.length, minimum.length);
  for (let index = 0; index < count; index += 1) {
    const lhs = candidate[index] ?? 0;
    const rhs = minimum[index] ?? 0;
    if (lhs !== rhs) return lhs > rhs;
  }
  return true;
}

function serializedRGBA(rgba) {
  const result = Buffer.alloc(32);
  rgba.forEach((component, index) => result.writeDoubleLE(component / 255, index * 8));
  return result;
}

export function patchRecords(palette) {
  const rgba = (color) => [color.red, color.green, color.blue, 255];
  return [
    {
      name: "bc16 light/universal",
      source: [22, 172, 102, 255],
      target: rgba(palette.light),
      expectedOccurrences: 2,
    },
    {
      name: "bc16 dark",
      source: [0, 212, 142, 255],
      target: rgba(palette.dark),
      expectedOccurrences: 1,
    },
    {
      name: "bg02 light/universal",
      source: [232, 247, 240, 255],
      target: rgba(palette.background),
      expectedOccurrences: 2,
    },
    {
      name: "bg03 light/universal",
      source: [0, 177, 118, 255],
      target: rgba(palette.light),
      expectedOccurrences: 2,
    },
    {
      name: "bg03 dark",
      source: [0, 168, 111, 255],
      target: rgba(palette.dark),
      expectedOccurrences: 1,
    },
    {
      name: "bg04 all appearances",
      source: [35, 200, 145, 255],
      target: rgba(palette.secondary),
      expectedOccurrences: 3,
    },
  ];
}

export function patchData(data, palette) {
  const output = Buffer.from(data);
  for (const record of patchRecords(palette)) {
    const source = serializedRGBA(record.source);
    const target = serializedRGBA(record.target);
    const offsets = [];
    let offset = output.indexOf(source);
    while (offset !== -1) {
      offsets.push(offset);
      offset = output.indexOf(source, offset + source.length);
    }
    if (offsets.length !== record.expectedOccurrences) {
      throw new AccentError(
        `颜色记录 ${record.name} 数量异常：预期 ${record.expectedOccurrences}，实际 ${offsets.length}。`,
      );
    }
    for (const targetOffset of offsets) target.copy(output, targetOffset);
  }
  return output;
}

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}

function run(executable, args, { allowFailure = false, stdio = "pipe" } = {}) {
  const result = spawnSync(executable, args, {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
    stdio,
  });
  if (result.error) throw result.error;
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  if (result.status !== 0 && !allowFailure) {
    throw new AccentError(`命令执行失败：${executable} ${args.join(" ")}\n${output}`);
  }
  return { output, status: result.status ?? 1 };
}

function plistValue(plistPath, key) {
  return run("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, plistPath]).output;
}

function loadMetadata(appPath) {
  const plistPath = path.join(appPath, "Contents/Info.plist");
  const metadata = {
    bundleIdentifier: plistValue(plistPath, "CFBundleIdentifier"),
    version: plistValue(plistPath, "CFBundleShortVersionString"),
    build: plistValue(plistPath, "CFBundleVersion"),
  };
  if (metadata.bundleIdentifier !== "com.tencent.inputmethod.wetype") {
    throw new AccentError(`不是受支持的微信输入法：${appPath}`);
  }
  return metadata;
}

function validateVersion(metadata) {
  if (!supportsVersion(metadata.version)) {
    throw new AccentError(
      `当前微信输入法 ${metadata.version}（${metadata.build}）低于最低支持版本 ${MINIMUM_WETYPE_VERSION}，或版本号无法识别。没有修改任何文件。`,
    );
  }
}

function assetsPath(appPath) {
  return path.join(appPath, "Contents/Resources/Assets.car");
}

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
  } catch {
    return null;
  }
}

function writeAtomic(filePath, data, sourceStat = null) {
  const temporaryPath = path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.${randomUUID()}.tmp`,
  );
  try {
    fs.writeFileSync(temporaryPath, data);
    if (sourceStat) {
      fs.chmodSync(temporaryPath, sourceStat.mode);
      fs.chownSync(temporaryPath, sourceStat.uid, sourceStat.gid);
    }
    fs.renameSync(temporaryPath, filePath);
  } finally {
    fs.rmSync(temporaryPath, { force: true });
  }
}

function writeState(state) {
  fs.mkdirSync(SUPPORT_PATH, { recursive: true });
  writeAtomic(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`);
}

function targetUserID() {
  return Number(process.env.SUDO_UID ?? process.getuid?.() ?? 0);
}

function weTypePIDs(userID, appPath) {
  const executable = path.join(path.resolve(appPath), "Contents/MacOS/WeType");
  const { output } = run("/bin/ps", ["-axo", "uid=,pid=,command="], { allowFailure: true });
  const pids = new Set();
  for (const line of output.split("\n")) {
    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(.+)$/);
    if (match && Number(match[1]) === userID && match[3] === executable) pids.add(match[2]);
  }
  return pids;
}

function sleep(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds);
}

function isRunning(pid) {
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch {
    return false;
  }
}

function waitForExit(pid) {
  for (let index = 0; index < 20 && isRunning(pid); index += 1) sleep(250);
}

function restartWeType(appPath) {
  const userID = targetUserID();
  const oldPIDs = weTypePIDs(userID, appPath);
  for (const pid of oldPIDs) {
    try {
      process.kill(Number(pid), "SIGTERM");
    } catch {}
    waitForExit(pid);
    if (isRunning(pid)) {
      try {
        process.kill(Number(pid), "SIGKILL");
      } catch {}
      waitForExit(pid);
    }
  }

  if (process.geteuid?.() === 0 && userID !== 0) {
    run("/bin/launchctl", [
      "asuser",
      String(userID),
      "/usr/bin/sudo",
      "-u",
      `#${userID}`,
      "/usr/bin/open",
      appPath,
    ]);
  } else {
    run("/usr/bin/open", [appPath]);
  }

  for (let index = 0; index < 20; index += 1) {
    const newPIDs = [...weTypePIDs(userID, appPath)].filter((pid) => !oldPIDs.has(pid));
    if (newPIDs.length > 0) return;
    sleep(250);
  }
  throw new AccentError("补丁写入后微信输入法没有成功重新启动，已尝试恢复原版。");
}

function backupPath(metadata, sourceHash) {
  return path.join(
    SUPPORT_PATH,
    "Backups",
    `${metadata.version}-${metadata.build}-${sourceHash.slice(0, 12)}`,
    "WeType.app",
  );
}

function validateBackup(candidate, metadata, expectedHash) {
  const backupMetadata = loadMetadata(candidate);
  if (backupMetadata.version !== metadata.version || backupMetadata.build !== metadata.build) {
    throw new AccentError(`备份属于另一版本的微信输入法：${candidate}`);
  }
  const actualHash = sha256(fs.readFileSync(assetsPath(candidate)));
  if (actualHash !== expectedHash) {
    throw new AccentError(`资源哈希不匹配。预期 ${expectedHash}，实际 ${actualHash}。`);
  }
  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", candidate]);
}

function ensureBackup(appPath, metadata, sourceHash) {
  const destination = backupPath(metadata, sourceHash);
  if (fs.existsSync(destination)) {
    validateBackup(destination, metadata, sourceHash);
    return destination;
  }
  const parent = path.dirname(destination);
  const temporary = path.join(parent, `.WeType.app.${randomUUID()}.tmp`);
  fs.mkdirSync(parent, { recursive: true });
  try {
    run("/usr/bin/ditto", ["--noextattr", "--noqtn", appPath, temporary]);
    validateBackup(temporary, metadata, sourceHash);
    fs.renameSync(temporary, destination);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
  return destination;
}

function restoreBackup(candidate, appPath, expectedHash, removeState) {
  if (!fs.existsSync(candidate)) throw new AccentError(`找不到原版备份：${candidate}`);
  run("/usr/bin/ditto", ["--noextattr", "--noqtn", candidate, appPath]);
  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
  const actualHash = sha256(fs.readFileSync(assetsPath(appPath)));
  if (actualHash !== expectedHash) {
    throw new AccentError(`资源哈希不匹配。预期 ${expectedHash}，实际 ${actualHash}。`);
  }
  restartWeType(appPath);
  if (removeState) fs.rmSync(STATE_PATH, { force: true });
}

function parseArguments(values) {
  const commands = new Set(["preview", "apply", "status", "restore", "doctor", "help", "version"]);
  const args = {
    command: "help",
    appPath: DEFAULT_APP_PATH,
    color: null,
    dark: null,
    secondary: null,
    background: null,
    yes: false,
  };
  let index = 0;
  if (values[0] && commands.has(values[0])) {
    args.command = values[0];
    index = 1;
  } else if (values[0] === "--help" || values[0] === "-h") {
    return args;
  } else if (values[0] === "--version" || values[0] === "-v") {
    args.command = "version";
    return args;
  } else if (values.length > 0) {
    args.command = "apply";
  }

  const valueOptions = new Map([
    ["--app", "appPath"],
    ["--color", "color"],
    ["--dark", "dark"],
    ["--secondary", "secondary"],
    ["--background", "background"],
  ]);
  while (index < values.length) {
    const value = values[index];
    if (value === "--yes" || value === "-y") {
      args.yes = true;
      index += 1;
      continue;
    }
    if (valueOptions.has(value)) {
      if (index + 1 >= values.length) throw new AccentError(`${value} 缺少参数。`);
      args[valueOptions.get(value)] = values[index + 1];
      index += 2;
      continue;
    }
    if (!value.startsWith("-") && !args.color) {
      args.color = value;
      index += 1;
      continue;
    }
    throw new AccentError(`未知参数：${value}`);
  }
  return args;
}

function printPalette(palette) {
  console.log(`浅色重点色：${colorHex(palette.light)}`);
  console.log(`深色重点色：${colorHex(palette.dark)}`);
  console.log(`次级重点色：${colorHex(palette.secondary)}`);
  console.log(`淡色背景：  ${colorHex(palette.background)}`);
}

async function confirm(prompt, yes) {
  if (yes) return true;
  const terminal = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    const answer = await terminal.question(`${prompt} [y/N] `);
    return answer.trim().toLowerCase() === "y";
  } finally {
    terminal.close();
  }
}

function elevate(originalArguments) {
  const scriptPath = fileURLToPath(import.meta.url);
  const elevatedArguments = originalArguments.includes("--yes")
    ? originalArguments
    : [...originalArguments, "--yes"];
  const result = spawnSync(
    "/usr/bin/sudo",
    [
      "/usr/bin/env",
      "WETYPE_ACCENT_ELEVATED=1",
      process.execPath,
      scriptPath,
      ...elevatedArguments,
    ],
    { stdio: "inherit" },
  );
  if (result.error) throw result.error;
  return result.status ?? 1;
}

function requireAdministrator() {
  if (process.geteuid?.() !== 0) throw new AccentError("此操作需要管理员权限。");
}

function stateForApp(metadata, appPath) {
  const state = loadState();
  if (
    state?.appPath === path.resolve(appPath) &&
    state.version === metadata.version &&
    state.build === metadata.build
  ) {
    return state;
  }
  return null;
}

function applyPatch(args, palette) {
  requireAdministrator();
  const appPath = path.resolve(args.appPath);
  const metadata = loadMetadata(appPath);
  validateVersion(metadata);
  const liveAssets = fs.readFileSync(assetsPath(appPath));
  const liveHash = sha256(liveAssets);
  const appState = stateForApp(metadata, appPath);

  let backup;
  let expectedOriginalHash;
  if (appState) {
    if (
      liveHash !== appState.originalAssetsSHA256 &&
      liveHash !== appState.patchedAssetsSHA256
    ) {
      throw new AccentError(
        `资源哈希不匹配。预期 ${appState.originalAssetsSHA256} 或 ${appState.patchedAssetsSHA256}，实际 ${liveHash}。`,
      );
    }
    backup = appState.backupPath;
    expectedOriginalHash = appState.originalAssetsSHA256;
    validateBackup(backup, metadata, expectedOriginalHash);
  } else {
    backup = ensureBackup(appPath, metadata, liveHash);
    expectedOriginalHash = liveHash;
  }

  const originalAssets = fs.readFileSync(assetsPath(backup));
  const originalHash = sha256(originalAssets);
  if (originalHash !== expectedOriginalHash) {
    throw new AccentError(`资源哈希不匹配。预期 ${expectedOriginalHash}，实际 ${originalHash}。`);
  }

  const patched = patchData(originalAssets, palette);
  const patchedHash = sha256(patched);
  const temporaryCatalog = path.join(os.tmpdir(), `wetype-accent-${randomUUID()}.car`);
  try {
    fs.writeFileSync(temporaryCatalog, patched);
    run("/usr/bin/assetutil", ["--validate-file", temporaryCatalog]);
  } finally {
    fs.rmSync(temporaryCatalog, { force: true });
  }

  const state = {
    appPath,
    version: metadata.version,
    build: metadata.build,
    originalAssetsSHA256: originalHash,
    patchedAssetsSHA256: patchedHash,
    backupPath: backup,
    light: colorHex(palette.light),
    dark: colorHex(palette.dark),
    secondary: colorHex(palette.secondary),
    background: colorHex(palette.background),
    appliedAt: new Date().toISOString(),
  };

  try {
    const liveAssetPath = assetsPath(appPath);
    writeAtomic(liveAssetPath, patched, fs.statSync(liveAssetPath));
    run("/usr/bin/codesign", [
      "--force",
      "--deep",
      "--sign",
      "-",
      "--preserve-metadata=identifier,entitlements",
      appPath,
    ]);
    run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
    writeState(state);
    restartWeType(appPath);
  } catch (error) {
    try {
      restoreBackup(backup, appPath, originalHash, false);
    } catch {}
    fs.rmSync(STATE_PATH, { force: true });
    throw error;
  }
  console.log("补丁已应用，微信输入法已重新启动。");
}

function restore(args) {
  requireAdministrator();
  const appPath = path.resolve(args.appPath);
  const metadata = loadMetadata(appPath);
  validateVersion(metadata);
  const state = stateForApp(metadata, appPath);
  if (!state) throw new AccentError("找不到与当前微信输入法版本匹配的补丁状态或备份。");
  restoreBackup(state.backupPath, appPath, state.originalAssetsSHA256, true);
  console.log("腾讯原版已恢复并重新启动。");
}

function status(args) {
  const appPath = path.resolve(args.appPath);
  const metadata = loadMetadata(appPath);
  const hash = sha256(fs.readFileSync(assetsPath(appPath)));
  console.log(`微信输入法：${metadata.version}（${metadata.build}）`);
  console.log(`资源 SHA-256：${hash}`);
  const state = stateForApp(metadata, appPath);
  if (hash === KNOWN_220_ASSETS_SHA256) {
    console.log("状态：已验证的腾讯原版资源");
  } else if (state && hash === state.patchedAssetsSHA256) {
    console.log("状态：已由 WeType Accent 修改");
    console.log(`颜色：${state.light} / ${state.dark}`);
    console.log(`备份：${state.backupPath}`);
  } else {
    console.log("状态：未识别为 WeType Accent 补丁");
  }
  const pids = [...weTypePIDs(targetUserID(), appPath)].sort();
  console.log(pids.length ? `进程：当前用户运行中（PID ${pids[0]}）` : "进程：当前用户未运行");
}

function doctor(args) {
  const appPath = path.resolve(args.appPath);
  const metadata = loadMetadata(appPath);
  validateVersion(metadata);
  run("/usr/bin/assetutil", ["--validate-file", assetsPath(appPath)]);
  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
  status(args);
  console.log("诊断：资源和代码签名验证通过。");
}

function help() {
  console.log(`WeType Accent — 自定义 macOS 微信输入法候选窗重点色

用法：
  npx wetype-accent --color '#007AFF'
  npx wetype-accent preview --color '#007AFF'
  npx wetype-accent status
  npx wetype-accent restore
  npx wetype-accent doctor

高级颜色参数：--dark '#0A84FF' --secondary '#409CFF' --background '#E8F2FF'
当前支持：微信输入法 >= ${MINIMUM_WETYPE_VERSION}

apply 和 restore 会在确认后自动请求管理员权限，请勿使用 sudo npx。`);
}

async function main() {
  const originalArguments = process.argv.slice(2);
  const args = parseArguments(originalArguments);
  switch (args.command) {
    case "preview": {
      if (!args.color) throw new AccentError("缺少 --color 参数。");
      printPalette(derivePalette(args));
      break;
    }
    case "apply": {
      if (!args.color) throw new AccentError("缺少 --color 参数。");
      const palette = derivePalette(args);
      if (!process.env.WETYPE_ACCENT_ELEVATED) printPalette(palette);
      if (!(await confirm("这会备份并重新签名微信输入法，继续吗？", args.yes))) {
        console.log("已取消，没有修改任何文件。");
        break;
      }
      if (process.geteuid?.() !== 0) process.exitCode = elevate(originalArguments);
      else applyPatch(args, palette);
      break;
    }
    case "restore": {
      if (!(await confirm("将恢复腾讯原版微信输入法，继续吗？", args.yes))) {
        console.log("已取消。");
        break;
      }
      if (process.geteuid?.() !== 0) process.exitCode = elevate(originalArguments);
      else restore(args);
      break;
    }
    case "status":
      status(args);
      break;
    case "doctor":
      doctor(args);
      break;
    case "version":
      console.log(`wetype-accent ${VERSION}`);
      break;
    default:
      help();
  }
}

const isDirectRun =
  process.argv[1] && fs.realpathSync(process.argv[1]) === fileURLToPath(import.meta.url);
if (isDirectRun) {
  main().catch((error) => {
    console.error(`错误：${error.message}`);
    process.exitCode = 1;
  });
}

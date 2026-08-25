import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  colorHex,
  derivePalette,
  parseHex,
  patchData,
  patchRecords,
  supportsVersion,
} from "../bin/wetype-accent.mjs";

function serializedRGBA(rgba) {
  const result = Buffer.alloc(32);
  rgba.forEach((component, index) => result.writeDoubleLE(component / 255, index * 8));
  return result;
}

test("解析十六进制颜色", () => {
  assert.deepEqual(parseHex("#0A84FF"), { red: 10, green: 132, blue: 255 });
  assert.equal(colorHex(parseHex("0a84ff")), "#0A84FF");
  assert.throws(() => parseHex("blue"), /无效颜色/);
});

test("自动生成辅助颜色", () => {
  const palette = derivePalette({ color: "#007AFF" });
  assert.equal(colorHex(palette.light), "#007AFF");
  assert.equal(colorHex(palette.dark), "#1485FF");
  assert.equal(colorHex(palette.secondary), "#409BFF");
  assert.equal(colorHex(palette.background), "#E6F2FF");
});

test("比较微信输入法版本", () => {
  for (const version of ["2.2", "2.2.0", "2.2.1", "2.10.0", "3.0.0"]) {
    assert.equal(supportsVersion(version), true);
  }
  for (const version of ["2.1.99", "1.99.99", "2.2.0-beta", "invalid"]) {
    assert.equal(supportsVersion(version), false);
  }
});

test("只替换预期数量的序列化颜色", () => {
  const palette = derivePalette({ color: "#007AFF" });
  const chunks = [Buffer.from("fixture")];
  for (const record of patchRecords(palette)) {
    for (let index = 0; index < record.expectedOccurrences; index += 1) {
      chunks.push(serializedRGBA(record.source), Buffer.from([0xde, 0xad, 0xbe, 0xef]));
    }
  }
  const fixture = Buffer.concat(chunks);
  const patched = patchData(fixture, palette);
  assert.equal(patched.length, fixture.length);
  assert.notDeepEqual(patched, fixture);
  assert.throws(() => patchData(Buffer.alloc(0), palette), /数量异常/);
});

test("可选真实 Assets.car 通过 Apple 校验", { skip: !process.env.WETYPE_ORIGINAL_ASSETS_FIXTURE }, () => {
  const source = fs.readFileSync(process.env.WETYPE_ORIGINAL_ASSETS_FIXTURE);
  const palette = derivePalette({
    color: "#007AFF",
    dark: "#0A84FF",
    secondary: "#409CFF",
    background: "#E8F2FF",
  });
  const destination = path.join(os.tmpdir(), `wetype-accent-real-${randomUUID()}.car`);
  try {
    fs.writeFileSync(destination, patchData(source, palette));
    const result = spawnSync("/usr/bin/assetutil", ["--validate-file", destination]);
    assert.equal(result.status, 0);
  } finally {
    fs.rmSync(destination, { force: true });
  }
});

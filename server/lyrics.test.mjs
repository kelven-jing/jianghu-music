import assert from "node:assert/strict";
import { activeLineIndex, parseLrc } from "./lyrics.mjs";

const lines = parseLrc(`
[00:01.50]第一句
[00:03.00]第二句
`);

assert.equal(lines.length, 2);
assert.equal(lines[0].text, "第一句");
assert.equal(lines[0].timeMs, 1500);
assert.equal(activeLineIndex(lines, 2000), 0);
assert.equal(activeLineIndex(lines, 3500), 1);

console.log("歌词解析测试通过");
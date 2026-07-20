#!/usr/bin/env node
// Runs the off-device BrightScript unit tests with the `brs` interpreter and turns the
// result into a real exit code so CI fails on a failing assertion. The interpreter itself
// always exits 0, so we scan its output for the harness markers instead.
//
// Two quirks of the `brs` CLI we work around:
//   1) it always exits 0, so we detect failures from the printed summary;
//   2) it walks the current working directory and crashes on a big tree like node_modules,
//      so we run it from an empty temp dir and hand it absolute file paths.
const { execFileSync } = require("child_process");
const { globSync } = require("glob");
const path = require("path");
const os = require("os");
const fs = require("fs");

const repoRoot = path.resolve(__dirname, "..");
const brsBin = path.join(repoRoot, "node_modules", ".bin", "brs");

// Source modules first, then the test harness, suites, and entry point. `brs` parses all
// files into one scope before running main(), so order only needs main() to exist.
const files = [
  ...globSync("source/**/*.brs", { cwd: repoRoot }),
  ...globSync("test/support/**/*.brs", { cwd: repoRoot }),
  ...globSync("test/**/*Tests.brs", { cwd: repoRoot }),
  "test/CleverTapTestMain.brs",
].map((f) => path.join(repoRoot, f));

const runDir = fs.mkdtempSync(path.join(os.tmpdir(), "ct-brs-"));

let output;
try {
  output = execFileSync(brsBin, files, { encoding: "utf8", stdio: "pipe", cwd: runDir });
} catch (err) {
  console.error(err.stdout || "");
  console.error(err.stderr || "");
  console.error("brs failed to run the test suite (likely a compile/runtime error).");
  process.exit(1);
} finally {
  fs.rmSync(runDir, { recursive: true, force: true });
}

process.stdout.write(output);

if (output.includes("TESTS FAILED") || !output.includes("TESTS PASSED")) {
  process.exit(1);
}

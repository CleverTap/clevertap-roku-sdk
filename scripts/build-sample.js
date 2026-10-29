#!/usr/bin/env node
// Builds the sideloadable sample channel zip from the SDK in this working tree.
//
// Why this exists: the sample consumes the SDK as a packed tarball pinned to a version
// number. The version rarely changes while the code does. npm compares the lockfile against
// that version, decides the requirement is already met, and skips the install. The sample
// then keeps running an old copy of the SDK. The symptom is confusing, because the zip
// builds and sideloads without complaint.
//
// So this script removes the installed copy and the lockfile before every build, then
// checks the result. The check compares each SDK module against the copy that landed in the
// sample. A stale file stops the build instead of reaching the device.
const { execFileSync } = require("child_process");
const rokuDeploy = require("roku-deploy");
const path = require("path");
const fs = require("fs");

const repoRoot = path.resolve(__dirname, "..");
const samplePath = path.join(repoRoot, "sample");
const zipPath = path.join(repoRoot, "clevertap-roku-sample.zip");
const pkg = require(path.join(repoRoot, "package.json"));
const tarball = `${pkg.name}-${pkg.version}.tgz`;

// npm ships as a .cmd shim on Windows.
const npm = process.platform === "win32" ? "npm.cmd" : "npm";

// With --check-only the script skips the pack and the reinstall. It just reports whether
// the sample folder currently holds this working tree. Use it to judge a zip you built
// earlier, without building a new one.
const checkOnly = process.argv.includes("--check-only");

function step(message) {
  console.log(`\n==> ${message}`);
}

function run(command, args, cwd) {
  execFileSync(command, args, { cwd: cwd, stdio: "inherit" });
}

function remove(target) {
  fs.rmSync(target, { recursive: true, force: true });
}

// --- 1. pack the SDK ---

if (!checkOnly) {
  step("Packing the SDK");
  // An old tarball with the same name would be picked up by the sample if packing failed.
  remove(path.join(repoRoot, tarball));
  run(npm, ["pack", "--silent"], repoRoot);
  if (!fs.existsSync(path.join(repoRoot, tarball))) {
    console.error(`npm pack did not produce ${tarball}.`);
    process.exit(1);
  }

  // --- 2. reinstall it into the sample ---

  step("Reinstalling the SDK into the sample");
  // These four are what npm and ropm leave behind. The lockfile is the one that causes the
  // stale install. The roku_modules folders matter because ropm copies files rather than
  // linking them, so a module deleted upstream would otherwise survive here.
  remove(path.join(samplePath, "package-lock.json"));
  remove(path.join(samplePath, "node_modules", pkg.name));
  remove(path.join(samplePath, "source", "roku_modules"));
  remove(path.join(samplePath, "components", "roku_modules"));

  run(npm, ["install", "--silent"], samplePath);
  run(path.join(samplePath, "node_modules", ".bin", "ropm"), ["install"], samplePath);
}

// --- 3. check that the sample really got this working tree ---

step("Checking the installed SDK matches the working tree");

// ropm copies each module into a folder named after the package, and renames every function
// inside it with a matching prefix. Read the folder name rather than guessing it.
const modulesDir = path.join(samplePath, "source", "roku_modules");
const installedDirs = fs.readdirSync(modulesDir);
if (installedDirs.length !== 1) {
  console.error(`Expected exactly one module in ${modulesDir}, found ${installedDirs.length}.`);
  process.exit(1);
}
const moduleName = installedDirs[0];
const prefix = new RegExp(`${moduleName}_`, "g");

const sourceDir = path.join(repoRoot, "source");
const problems = [];

for (const file of fs.readdirSync(sourceDir).filter((f) => f.endsWith(".brs"))) {
  const installedPath = path.join(modulesDir, moduleName, file);
  if (!fs.existsSync(installedPath)) {
    problems.push(`${file} is missing from the sample`);
    continue;
  }
  // Undo the rename, then the two copies should be identical.
  const original = fs.readFileSync(path.join(sourceDir, file), "utf8");
  const installed = fs.readFileSync(installedPath, "utf8").replace(prefix, "");
  if (original !== installed) {
    problems.push(`${file} in the sample differs from source/${file}`);
  }
}

if (problems.length > 0) {
  console.error("\nThe sample is not running this working tree:");
  for (const problem of problems) {
    console.error(`  - ${problem}`);
  }
  console.error("\nDelete sample/node_modules and try again.");
  process.exit(1);
}
console.log(`${moduleName}: every module matches source/`);

// --- 4. zip it ---

if (checkOnly) {
  process.exit(0);
}

step("Building the channel zip");
remove(zipPath);
// Roku reads the manifest from the top of the archive, so the sample folder is the root.
// Everything else in that folder is build tooling the channel does not need.
rokuDeploy
  .zipFolder(samplePath, zipPath, undefined, [
    "manifest",
    "source/**/*",
    "components/**/*",
    "images/**/*",
    "!**/.DS_Store",
  ])
  .then(() => {
    console.log(`\nSideload this: ${zipPath}`);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });

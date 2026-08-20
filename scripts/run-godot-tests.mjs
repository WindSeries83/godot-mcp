#!/usr/bin/env node
// Runs test/godot/run_tests.gd under a real Godot binary. Separate from
// `npm test` (vitest) because it needs a local Godot install that CI/dev
// machines won't always have — this script fails soft (exit 0, clear
// message) when no `godot` binary is found, rather than breaking `npm test`
// for everyone. Pass --require-godot (or set GODOT_REQUIRED=1) to instead
// exit 1 when no binary is found — used by the CI job that's supposed to
// actually have one, so a missing binary there fails loudly instead of the
// job going green while testing nothing.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { cpSync, rmSync } from "node:fs";

const repoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const fixtureProject = path.join(repoRoot, "test", "godot");

const requireGodot = process.argv.includes("--require-godot") || process.env.GODOT_REQUIRED === "1";

const candidates = [process.env.GODOT_BIN, "godot4", "godot"].filter(Boolean);

let bin = null;
for (const candidate of candidates) {
  const probe = spawnSync(candidate, ["--version"], { encoding: "utf8" });
  if (probe.status === 0) { bin = candidate; break; }
}

if (!bin) {
  const message = "No Godot binary found (tried: " + candidates.join(", ") + "). " +
    "Set GODOT_BIN or put `godot`/`godot4` on PATH to run test/godot/run_tests.gd.";
  if (requireGodot) {
    console.error(message);
    process.exit(1);
  }
  console.log(`${message} Skipping.`);
  process.exit(0);
}

// command_router.gd preload()s its 26 command modules by res:// path, and
// preload() is resolved at parse time — before any of run_tests.gd's own
// code runs. Since res:// always means "this project's root" regardless of
// how the script itself was load()ed, command_router.gd can only ever parse
// successfully inside a project that actually has an addons/godot_mcp/ at
// its root, which this fixture project deliberately doesn't keep committed
// (see test/godot/project.godot's comment). So: stage an ephemeral copy of
// plugin/ here before running, and remove it after — the repo's source of
// truth stays exactly plugin/, nothing here is meant to be committed.
const fixtureAddonDir = path.join(fixtureProject, "addons", "godot_mcp");
cpSync(path.join(repoRoot, "plugin"), fixtureAddonDir, { recursive: true });

let status = 1;
try {
  console.log(`Running headless GDScript tests with ${bin}...`);
  const result = spawnSync(
    bin,
    ["--headless", "--path", fixtureProject, "--script", "res://run_tests.gd"],
    { stdio: "inherit" }
  );
  status = result.status ?? 1;
} finally {
  rmSync(fixtureAddonDir, { recursive: true, force: true });
}

process.exit(status);

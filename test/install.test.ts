import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { installAddon } from "../src/index.js";

describe("installAddon", () => {
  let target: string;

  beforeEach(() => {
    target = mkdtempSync(path.join(tmpdir(), "godot-hands-install-"));
  });

  afterEach(() => {
    rmSync(target, { recursive: true, force: true });
  });

  it("copies plugin/ into <project>/addons/godot_mcp/", () => {
    const dest = installAddon(target);
    expect(dest).toBe(path.join(target, "addons", "godot_mcp"));
    expect(existsSync(path.join(dest, "plugin.cfg"))).toBe(true);
    expect(existsSync(path.join(dest, "plugin.gd"))).toBe(true);
    expect(existsSync(path.join(dest, "commands", "scene_commands.gd"))).toBe(true);
    expect(existsSync(path.join(dest, "utils", "node_utils.gd"))).toBe(true);
  });
});

import { describe, it, expect } from "vitest";
import { RESOURCE_DEFS, PROMPT_DEFS } from "../src/index.js";

describe("RESOURCE_DEFS", () => {
  it("has no duplicate uris", () => {
    const uris = RESOURCE_DEFS.map((r) => r.uri);
    expect(new Set(uris).size).toBe(uris.length);
  });

  it("every uri uses the godot:// scheme", () => {
    for (const r of RESOURCE_DEFS) expect(r.uri.startsWith("godot://")).toBe(true);
  });

  it("includes the resources named in the roadmap", () => {
    const uris = RESOURCE_DEFS.map((r) => r.uri);
    expect(uris).toContain("godot://scene/current");
    expect(uris).toContain("godot://project/settings");
    expect(uris).toContain("godot://logs/recent");
  });
});

describe("PROMPT_DEFS", () => {
  it("has no duplicate names", () => {
    const names = PROMPT_DEFS.map((p) => p.name);
    expect(new Set(names).size).toBe(names.length);
  });

  it("includes the prompts named in the roadmap", () => {
    const names = PROMPT_DEFS.map((p) => p.name);
    expect(names).toEqual(
      expect.arrayContaining(["blockout-3d-level", "diagnose-crash", "audit-scene-perf", "asset-strategy"])
    );
  });

  it("render() fills in supplied arguments and returns non-empty text", () => {
    for (const p of PROMPT_DEFS) {
      const args: Record<string, string> = {};
      for (const a of p.arguments) args[a.name] = `test-${a.name}`;
      const text = p.render(args);
      expect(text.length).toBeGreaterThan(0);
      for (const a of p.arguments) {
        if (a.required) expect(text).toContain(`test-${a.name}`);
      }
    }
  });

  it("every declared argument has a non-empty description", () => {
    for (const p of PROMPT_DEFS) {
      for (const a of p.arguments) expect(a.description.length).toBeGreaterThan(0);
    }
  });
});

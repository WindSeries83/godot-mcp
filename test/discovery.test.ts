import { describe, it, expect } from "vitest";
import { levenshtein, suggestMethod, truncateOutput } from "../src/index.js";

describe("levenshtein", () => {
  it("is 0 for identical strings", () => {
    expect(levenshtein("add_node", "add_node")).toBe(0);
  });

  it("counts a single substitution", () => {
    expect(levenshtein("add_node", "add_nodo")).toBe(1);
  });

  it("counts insertions/deletions", () => {
    expect(levenshtein("add_node", "add_nod")).toBe(1);
  });
});

describe("suggestMethod", () => {
  const known = ["add_node", "delete_node", "update_property", "get_scene_tree", "add_resource"];

  it("returns null for an exact match (nothing to suggest)", () => {
    expect(suggestMethod("add_node", known)).toBeNull();
  });

  it("suggests the closest name for a small typo", () => {
    expect(suggestMethod("add_nde", known)).toBe("add_node");
  });

  it("suggests nothing for a name that isn't plausibly a typo", () => {
    expect(suggestMethod("completely_unrelated_xyz", known)).toBeNull();
  });
});

describe("truncateOutput", () => {
  it("leaves short output untouched", () => {
    expect(truncateOutput("hello", 100)).toBe("hello");
  });

  it("truncates and notes how much was cut", () => {
    const text = "x".repeat(1000);
    const result = truncateOutput(text, 100);
    expect(result.startsWith("x".repeat(100))).toBe(true);
    expect(result).toContain("truncated 900 of 1000 characters");
  });
});

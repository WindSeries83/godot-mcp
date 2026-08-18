import { describe, it, expect } from "vitest";
import { pickDefaultResolution, pickDefaultFormat } from "../src/assets/polyhaven.js";

describe("pickDefaultResolution", () => {
  it("prefers 1k when available, even if larger resolutions exist", () => {
    const files = {
      Diffuse: { "1k": {}, "2k": {}, "4k": {}, "8k": {} },
    } as any;
    expect(pickDefaultResolution(files)).toBe("1k");
  });

  it("falls back to the smallest available resolution when 1k is missing", () => {
    const files = {
      Diffuse: { "2k": {}, "4k": {} },
    } as any;
    expect(pickDefaultResolution(files)).toBe("2k");
  });

  it("looks across every map type, not just the first", () => {
    const files = {
      Diffuse: { "4k": {} },
      Rough: { "1k": {}, "4k": {} },
    } as any;
    expect(pickDefaultResolution(files)).toBe("1k");
  });
});

describe("pickDefaultFormat", () => {
  it("always picks gltf for the gltf map type", () => {
    expect(pickDefaultFormat("gltf", { gltf: {} as any })).toBe("gltf");
  });

  it("prefers jpg over png/exr for texture maps", () => {
    const atRes = { jpg: {}, png: {}, exr: {} } as any;
    expect(pickDefaultFormat("diffuse", atRes)).toBe("jpg");
  });

  it("falls back to png when jpg isn't available", () => {
    const atRes = { png: {}, exr: {} } as any;
    expect(pickDefaultFormat("nor_gl", atRes)).toBe("png");
  });

  it("falls back to whatever format exists when none of the preferred ones are present", () => {
    const atRes = { tiff: {} } as any;
    expect(pickDefaultFormat("displacement", atRes)).toBe("tiff");
  });
});

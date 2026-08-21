import { describe, it, expect, beforeEach, vi } from "vitest";
import { GodotBridge } from "../src/index.js";

describe("GodotBridge job registry", () => {
  let bridge: GodotBridge;

  beforeEach(() => {
    bridge = new GodotBridge();
    vi.restoreAllMocks();
  });

  it("returns a job id immediately without waiting for the call", async () => {
    let resolveCall: (v: unknown) => void = () => {};
    vi.spyOn(bridge, "call").mockReturnValue(new Promise((res) => { resolveCall = res; }));

    const id = bridge.startJob("run_stress_test", { duration: 60 });
    expect(typeof id).toBe("string");
    expect(bridge.getJob(id)?.status).toBe("running");

    resolveCall({ events_sent: 900 });
    await vi.waitFor(() => expect(bridge.getJob(id)?.status).toBe("done"));
    expect(bridge.getJob(id)?.result).toEqual({ events_sent: 900 });
  });

  it("records a failed call as an errored job rather than throwing", async () => {
    vi.spyOn(bridge, "call").mockRejectedValue(new Error("no scene playing"));

    const id = bridge.startJob("run_test_scenario", {});
    await vi.waitFor(() => expect(bridge.getJob(id)?.status).toBe("error"));
    expect(bridge.getJob(id)?.error).toContain("no scene playing");
  });

  it("gives each job a distinct id", () => {
    vi.spyOn(bridge, "call").mockReturnValue(new Promise(() => {}));
    const a = bridge.startJob("run_stress_test", {});
    const b = bridge.startJob("run_stress_test", {});
    expect(a).not.toBe(b);
  });

  it("returns undefined for an unknown job id", () => {
    expect(bridge.getJob("nope")).toBeUndefined();
  });

  it("passes a longer timeout than the default 30s request timeout", () => {
    const spy = vi.spyOn(bridge, "call").mockReturnValue(new Promise(() => {}));
    bridge.startJob("run_stress_test", { duration: 60 });
    const timeoutArg = spy.mock.calls[0][2] as number;
    expect(timeoutArg).toBeGreaterThan(30_000);
  });
});

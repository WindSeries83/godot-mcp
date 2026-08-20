import { describe, it, expect } from "vitest";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checkContract } from "../scripts/contract-check.mjs";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

describe("addon/router contract", () => {
  it("every command module is registered, and get_commands()/get_command_schemas() agree", () => {
    const { errors } = checkContract(repoRoot);
    expect(errors).toEqual([]);
  });
});

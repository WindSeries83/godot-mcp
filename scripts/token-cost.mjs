#!/usr/bin/env node
// Measures the token weight of this server's actual tool surface (the 9
// godot_* tools in TOOL_DEFS), and — if a Godot editor is connected —
// the counterfactual of exposing every addon method as its own MCP tool
// instead, the design this repo deliberately avoids in favor of godot_call
// + live discovery (describe_methods/describe_method). Run with:
//   npm run build && npm run token-cost
// (needs a build because it imports from dist/, and needs a running,
// connected Godot editor for the counterfactual — otherwise that part is
// skipped with a note, since it's the only piece that needs live data).
import { TOOL_DEFS, GodotBridge } from "../dist/index.js";

// Rough, provider-agnostic estimate — about 4 bytes per token for JSON-ish
// text, the same ballpark rule of thumb the breakpoint-mcp README uses for
// the number this script exists to compare against. Good enough for an
// order-of-magnitude comparison, not billing.
function estimateTokens(bytes) {
  return Math.round(bytes / 4);
}

function measure(defs) {
  const json = JSON.stringify(defs);
  const bytes = Buffer.byteLength(json, "utf8");
  return { bytes, tokens: estimateTokens(bytes), count: defs.length };
}

const ours = measure(TOOL_DEFS);
console.log("This server's actual tool surface:");
console.log(`  ${ours.count} tools, ${ours.bytes.toLocaleString()} bytes, ~${ours.tokens.toLocaleString()} tokens upfront.`);
console.log();

const godot = new GodotBridge();
await godot.start();

const connected = await new Promise((resolve) => {
  const deadline = Date.now() + 3000;
  const poll = setInterval(() => {
    if (godot.connectedPeerCount > 0) { clearInterval(poll); resolve(true); }
    else if (Date.now() > deadline) { clearInterval(poll); resolve(false); }
  }, 100);
});

if (!connected) {
  console.log("No Godot editor connected within 3s — skipping the per-method counterfactual.");
  console.log("Start Godot with the addon enabled and re-run for the full comparison.");
  godot.stop();
  process.exit(0);
}

try {
  const known = await godot.call("describe_methods", {});
  const names = Object.keys(known);
  const full = await godot.call("describe_method", { methods: names });
  const counterfactual = measure(Object.entries(full).map(([name, schema]) => ({ name, ...schema })));

  console.log(`Counterfactual — if all ${counterfactual.count} addon methods were exposed as individual MCP tools:`);
  console.log(`  ${counterfactual.bytes.toLocaleString()} bytes, ~${counterfactual.tokens.toLocaleString()} tokens upfront.`);
  console.log();
  const ratio = (counterfactual.tokens / ours.tokens).toFixed(1);
  console.log(`This server's actual surface is ~${ratio}x smaller in upfront token cost.`);
} finally {
  godot.stop();
}

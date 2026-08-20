#!/usr/bin/env node
// Static contract check between the Godot addon's command modules
// (plugin/commands/*.gd) and command_router.gd, plus the small set of
// method names src/index.ts calls by name directly.
//
// This never touches a running editor — it parses the .gd/.ts source with
// regexes matched to the exact, hand-checked shape those files use
// (tabs, one key per line). It exists to catch drift that would otherwise
// go unnoticed at compile time: command_router.gd is deliberately lenient
// (a handler with no schema, or vice versa, is silently accepted — see the
// comment at command_router.gd's registration loop), and nothing else
// verifies that get_commands() and get_command_schemas() agree, that every
// module file is actually registered, or that the method names src/index.ts
// hardcodes still exist on the addon side.

import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Method names src/index.ts calls directly by name (outside godot_call's
// live-validated path), collected from RESOURCE_DEFS/PROMPT_DEFS fetchers
// and the dedicated tool handlers. Kept here (not derived from src/index.ts)
// so a rename on the TS side that forgets to update this list still fails
// loudly, rather than the check silently validating against its own drift.
const TS_HARDCODED_METHODS = [
  "describe_methods",
  "describe_method",
  "get_scene_tree",
  "get_project_info",
  "get_project_settings",
  "get_output_log",
  "classdb_describe",
  "get_editor_screenshot",
  "execute_editor_script",
  "reload_project",
];

const META_METHODS = ["get_available_methods", "describe_methods", "describe_method"];

function extractRegisteredModules(routerSrc) {
  // Modules are listed by basename in _BUILTIN_MODULES and load()ed at
  // runtime (not preload()ed at compile time), so one module failing to
  // parse degrades the surface instead of killing the whole plugin.
  const block = /const _BUILTIN_MODULES: Array\[String\] = \[([\s\S]*?)\n\]/.exec(routerSrc);
  if (!block) throw new Error("Could not find _BUILTIN_MODULES array in command_router.gd");
  const modules = [];
  const re = /"([a-zA-Z0-9_]+)"/g;
  let m;
  while ((m = re.exec(block[1]))) modules.push(m[1] + ".gd");
  return modules;
}

function extractDictBlock(src, funcName) {
  // Matches `func <funcName>() -> Dictionary:` through the next top-level
  // `func ` at column 0, or end of file.
  const funcRe = new RegExp(`func ${funcName}\\(\\) -> Dictionary:\\n([\\s\\S]*?)(?=\\nfunc |\\n@tool|$)`);
  const m = funcRe.exec(src);
  return m ? m[1] : null;
}

function extractCommandKeys(block) {
  // "method_name": _handler_name,
  const re = /^\t\t"([a-zA-Z0-9_]+)":\s*_[a-zA-Z0-9_]+,\s*$/gm;
  const keys = [];
  let m;
  while ((m = re.exec(block))) keys.push(m[1]);
  return keys;
}

function extractSchemaEntries(block) {
  // "method_name": {  ... opening a schema dict at the same two-tab indent.
  // We only need the key and whether its body contains the required fields —
  // grab each key's span up to the next same-indent key or the end of block.
  const keyRe = /^\t\t"([a-zA-Z0-9_]+)": \{\s*$/gm;
  const starts = [];
  let m;
  while ((m = keyRe.exec(block))) starts.push({ name: m[1], index: m.index });
  const entries = [];
  for (let i = 0; i < starts.length; i++) {
    const start = starts[i].index;
    const end = i + 1 < starts.length ? starts[i + 1].index : block.length;
    entries.push({ name: starts[i].name, body: block.slice(start, end) });
  }
  return entries;
}

function checkSchemaShape(entry) {
  const missing = [];
  if (!/"category":/.test(entry.body)) missing.push("category");
  if (!/"summary":/.test(entry.body)) missing.push("summary");
  if (!/"params":/.test(entry.body)) missing.push("params");
  const annMatch = /"annotations":\s*\{([^}]*)\}/.exec(entry.body);
  if (!annMatch) {
    missing.push("annotations");
  } else {
    for (const flag of ["readOnly", "destructive", "idempotent"]) {
      if (!new RegExp(`"${flag}":\\s*(true|false)`).test(annMatch[1])) missing.push(`annotations.${flag}`);
    }
  }
  return missing;
}

function hasConfirmAnnotation(entry) {
  const annMatch = /"annotations":\s*\{([^}]*)\}/.exec(entry.body);
  return !!annMatch && /"confirm":\s*true/.test(annMatch[1]);
}

export function checkContract(repoRoot) {
  const errors = [];
  const pluginDir = path.join(repoRoot, "plugin");
  const commandsDir = path.join(pluginDir, "commands");
  const routerSrc = readFileSync(path.join(pluginDir, "command_router.gd"), "utf8");

  const registeredModules = new Set(extractRegisteredModules(routerSrc));

  const filesOnDisk = readdirSync(commandsDir)
    .filter((f) => f.endsWith(".gd") && f !== "base_command.gd");

  // Check 1: every module file on disk is registered in command_router.gd.
  for (const file of filesOnDisk) {
    if (!registeredModules.has(file)) {
      errors.push(`plugin/commands/${file} exists but is not listed in command_router.gd's _BUILTIN_MODULES array — it is dead code and will silently register no methods.`);
    }
  }
  for (const registered of registeredModules) {
    if (!filesOnDisk.includes(registered)) {
      errors.push(`command_router.gd registers plugin/commands/${registered} but that file does not exist.`);
    }
  }

  const allHandlerKeys = new Map(); // method_name -> file
  const allSchemaKeys = new Map(); // method_name -> file
  const confirmMethods = new Set();

  for (const file of filesOnDisk) {
    if (!registeredModules.has(file)) continue; // already reported above
    const src = readFileSync(path.join(commandsDir, file), "utf8");

    const commandsBlock = extractDictBlock(src, "get_commands");
    const schemasBlock = extractDictBlock(src, "get_command_schemas");

    const commandKeys = commandsBlock ? extractCommandKeys(commandsBlock) : [];
    const schemaEntries = schemasBlock ? extractSchemaEntries(schemasBlock) : [];
    const schemaKeySet = new Set(schemaEntries.map((e) => e.name));
    const commandKeySet = new Set(commandKeys);

    // Check 2: get_commands() and get_command_schemas() must have identical key sets.
    for (const key of commandKeys) {
      if (!schemaKeySet.has(key)) {
        errors.push(`${file}: method "${key}" is registered in get_commands() but has no entry in get_command_schemas().`);
      }
    }
    for (const entry of schemaEntries) {
      if (!commandKeySet.has(entry.name)) {
        errors.push(`${file}: get_command_schemas() has an entry for "${entry.name}" but get_commands() does not register it.`);
      }
    }

    // Check 3: every schema entry has category, summary, params, and the three annotation flags.
    for (const entry of schemaEntries) {
      const missing = checkSchemaShape(entry);
      if (missing.length) {
        errors.push(`${file}: schema for "${entry.name}" is missing ${missing.join(", ")}.`);
      }
      if (hasConfirmAnnotation(entry)) confirmMethods.add(entry.name);
    }

    // Check 4: collect for cross-module duplicate detection.
    for (const key of commandKeys) {
      if (allHandlerKeys.has(key)) {
        errors.push(`Method "${key}" is registered in both ${allHandlerKeys.get(key)} and ${file} — command_router.gd's registration loop will silently let the later one win.`);
      } else {
        allHandlerKeys.set(key, file);
      }
    }
    for (const entry of schemaEntries) {
      allSchemaKeys.set(entry.name, file);
    }
  }

  // Meta methods (get_available_methods, describe_methods, describe_method)
  // live in command_router.gd itself, not in any module.
  for (const name of META_METHODS) {
    allHandlerKeys.set(name, "command_router.gd");
    allSchemaKeys.set(name, "command_router.gd");
  }

  // Check 5: method names src/index.ts hardcodes must exist on the addon side.
  const knownMethods = new Set([...allHandlerKeys.keys()]);
  for (const name of TS_HARDCODED_METHODS) {
    if (!knownMethods.has(name)) {
      errors.push(`src/index.ts calls "${name}" directly by name, but no addon module (or command_router.gd) registers it.`);
    }
  }

  // Check 6: confirm:true methods must exist (trivially true here since we
  // only collect confirmMethods from real schema entries, but this guards
  // against a future refactor that builds the confirm list from elsewhere).
  for (const name of confirmMethods) {
    if (!knownMethods.has(name)) {
      errors.push(`"${name}" is marked annotations.confirm:true but is not a registered method.`);
    }
  }

  return { errors, methodCount: knownMethods.size, confirmMethods: [...confirmMethods].sort() };
}

// CLI guard
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const repoRoot = path.resolve(__dirname, "..");
  const { errors, methodCount, confirmMethods } = checkContract(repoRoot);
  if (errors.length) {
    console.error(`contract-check: ${errors.length} problem(s) found across ${methodCount} registered methods:\n`);
    for (const e of errors) console.error(`  - ${e}`);
    process.exit(1);
  }
  console.log(`contract-check: OK — ${methodCount} methods registered, ${confirmMethods.length} require confirm:true.`);
}

[🇫🇷 Français](#fr) · [🇬🇧 English](#en)

---

# <a id="fr"></a>godot-mcp

Pont MCP entre un assistant IA et l'éditeur Godot.

```
Assistant IA <---stdio/MCP---> godot-mcp <---WebSocket:6505---> Plugin Godot
```

**6 outils MCP** pour piloter l'éditeur : `godot_call` (175+ méthodes), `godot_list_methods`, `godot_info`, `godot_screenshot`, `godot_execute`, `godot_status`.

## Installation

### 1. Plugin Godot

Copiez le dossier `plugin/` dans `addons/godot_mcp/` de votre projet Godot.

```
votre-projet/
└── addons/
    └── godot_mcp/       ← copiez plugin/ ici
```

Activez-le : **Projet → Paramètres du projet → Plugins → godot-mcp → Activer**

### 2. Serveur

```bash
npm install && npm run build && npm start
```

### 3. Client MCP

Ajoutez à la config de votre client IA (`.mcp.json`, `claude.json`, `opencode.json`) :

```json
{
  "mcpServers": {
    "godot-mcp": {
      "command": "node",
      "args": ["/chemin/vers/godot-mcp/dist/index.js"]
    }
  }
}
```

## Outils

| Outil | Description |
|-------|-------------|
| `godot_call` | Appelle n'importe quelle méthode (175+) |
| `godot_list_methods` | Liste les méthodes par catégorie |
| `godot_info` | Infos projet |
| `godot_screenshot` | Capture éditeur en PNG |
| `godot_execute` | Exécute du GDScript |
| `godot_status` | Vérifie la connexion |

> **Chemins de nodes** : les paramètres `parent_path` et `node_path` de
> `godot_call` (ex. `add_node`, `update_property`, `delete_node`) sont
> **toujours relatifs à la racine de la scène actuellement éditée** (`"."` =
> racine de la scène). Les chemins absolus Godot (`"/root"`, `"../..."`) sont
> rejetés — ils cibleraient l'arbre interne de l'éditeur au lieu de la scène.
>
> **`godot_screenshot`** nécessite un éditeur avec rendu actif : il ne
> fonctionne pas en mode `--headless` (erreur "Could not get image from
> viewport").

## Arborescence

```
godot-mcp/
├── plugin/              ← Plugin Godot (à copier dans votre projet)
├── src/index.ts         ← Serveur MCP (Node.js)
├── package.json
├── tsconfig.json
├── README.md
└── LICENSE              ← MIT
```

## Licence

MIT

Ce plugin Godot dérive de [godot-mcp-pro](https://github.com/youichi-uda/godot-mcp-pro) (Youichi Uda, MIT).

---

# <a id="en"></a>godot-mcp

MCP bridge between an AI assistant and the Godot editor.

```
AI Assistant <---stdio/MCP---> godot-mcp <---WebSocket:6505---> Godot Plugin
```

**6 MCP tools** to control the editor: `godot_call` (175+ methods), `godot_list_methods`, `godot_info`, `godot_screenshot`, `godot_execute`, `godot_status`.

## Setup

### 1. Godot Plugin

Copy the `plugin/` folder into your project's `addons/godot_mcp/`.

```
your-project/
└── addons/
    └── godot_mcp/       ← copy plugin/ here
```

Enable it: **Project → Project Settings → Plugins → godot-mcp → Enable**

### 2. Server

```bash
npm install && npm run build && npm start
```

### 3. MCP Client

Add to your AI client config (`.mcp.json`, `claude.json`, `opencode.json`):

```json
{
  "mcpServers": {
    "godot-mcp": {
      "command": "node",
      "args": ["/path/to/godot-mcp/dist/index.js"]
    }
  }
}
```

## Tools

| Tool | Description |
|------|-------------|
| `godot_call` | Call any method (175+) |
| `godot_list_methods` | List methods by category |
| `godot_info` | Project info |
| `godot_screenshot` | Editor screenshot in PNG |
| `godot_execute` | Run GDScript |
| `godot_status` | Check connection |

> **Node paths**: `parent_path` and `node_path` parameters of `godot_call`
> (e.g. `add_node`, `update_property`, `delete_node`) are **always relative to
> the root of the currently edited scene** (`"."` = scene root). Absolute
> Godot paths (`"/root"`, `"../..."`) are rejected — they would target the
> editor's internal tree instead of the scene.
>
> **`godot_screenshot`** requires an editor with active rendering: it does not
> work in `--headless` mode ("Could not get image from viewport" error).

## Structure

```
godot-mcp/
├── plugin/              ← Godot plugin (copy to your project)
├── src/index.ts         ← MCP server (Node.js)
├── package.json
├── tsconfig.json
├── README.md
└── LICENSE              ← MIT
```

## License

MIT

This Godot plugin is derived from [godot-mcp-pro](https://github.com/youichi-uda/godot-mcp-pro) (Youichi Uda, MIT).

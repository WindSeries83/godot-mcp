[🇫🇷 Français](#fr) · [🇬🇧 English](#en)

---

# <a id="fr"></a>godot-mcp

Pont MCP entre un assistant IA et l'éditeur Godot.

```
Assistant IA <---stdio/MCP---> godot-mcp <---WebSocket:6505---> Plugin Godot
```

**7 outils MCP** pour piloter l'éditeur : `godot_call` (toutes les méthodes de l'addon — le catalogue est découvert en direct, jamais figé dans ce dépôt), `godot_list_methods`, `godot_describe`, `godot_info`, `godot_screenshot`, `godot_execute`, `godot_status`.

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
| `godot_call` | Appelle n'importe quelle méthode |
| `godot_list_methods` | Liste les méthodes par catégorie (en direct depuis l'éditeur connecté) |
| `godot_describe` | Schéma complet (paramètres, types, annotations) d'une ou plusieurs méthodes |
| `godot_info` | Infos projet |
| `godot_screenshot` | Capture éditeur en PNG |
| `godot_execute` | Exécute du GDScript |
| `godot_status` | Vérifie la connexion |
| `godot_assets` | Recherche/prévisualise/importe des assets CC0 (Poly Haven, ambientCG) |

> **`godot_assets`** effectue des requêtes réseau sortantes vers `polyhaven.com`
> et `ambientcg.com`. `import` écrit les fichiers dans
> `<projet>/assets/<provider>/<id>/` (chemin obtenu via `get_project_info`)
> puis déclenche un rescan du projet. Sources CC0 uniquement (domaine
> public, aucune attribution légalement requise) ; une note `NOTICE.txt`
> est écrite à côté de chaque asset importé.

> **Chemins de nodes** : les paramètres `parent_path` et `node_path` de
> `godot_call` (ex. `add_node`, `update_property`, `delete_node`) sont
> **toujours relatifs à la racine de la scène actuellement éditée** (`"."` =
> racine de la scène). Les chemins absolus Godot (`"/root"`, `"../..."`) sont
> rejetés — ils cibleraient l'arbre interne de l'éditeur au lieu de la scène.
>
> **Handles de session** : tout paramètre `node_path` accepte aussi un
> handle (chaîne `"@id:<n>"`, renvoyée sous `"handle"` par `get_scene_tree`,
> `add_node`, `rename_node`, etc.) à la place d'un chemin. Un handle continue
> de désigner le même node après un renommage ou un déplacement dans la
> scène, contrairement à un chemin qui casse dès que l'un des deux se
> produit — utile pour enchaîner plusieurs appels sur le node qu'on vient de
> créer/modifier. Un handle expire si la scène est rechargée/refermée ;
> rappelez `get_scene_tree` pour en obtenir un nouveau.
>
> **`godot_screenshot`** nécessite un éditeur avec rendu actif : il ne
> fonctionne pas en mode `--headless` (erreur "Could not get image from
> viewport").

## Ressources et prompts MCP

En plus des outils, le serveur expose l'état du projet en **ressources**
(gratuites en tokens tant qu'elles ne sont pas lues, contrairement aux
outils) : `godot://scene/current`, `godot://project/info`,
`godot://project/settings`, `godot://logs/recent`, et le template
`godot://class/{name}` (réflexion ClassDB, mise en cache 5 min — les classes
du moteur ne changent pas en cours de session).

Quatre **prompts** réutilisables guident les workflows pour lesquels ce
serveur a été conçu : `blockout-3d-level`, `diagnose-crash`,
`audit-scene-perf`, `asset-strategy`.

`godot_assets {action: "import"}` envoie des notifications de progression
(`notifications/progress`) si le client fournit un `progressToken` — le
téléchargement peut prendre du temps sur une connexion lente.

## Arborescence

```
godot-mcp/
├── plugin/              ← Plugin Godot (à copier dans votre projet)
├── src/index.ts         ← Serveur MCP (Node.js)
├── src/assets/          ← Sourcing d'assets CC0 (Poly Haven, ambientCG)
├── package.json
├── tsconfig.json
├── README.md
└── LICENSE              ← MIT
```

## Développement

```bash
npm test          # tests unitaires (vitest) : framing WS, dispatch JSON-RPC
npm run test:godot # tests GDScript en --headless (nécessite `godot`/`godot4` sur le PATH ou GODOT_BIN)
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

**7 MCP tools** to control the editor: `godot_call` (every addon method — the catalog is discovered live, never hardcoded in this repo), `godot_list_methods`, `godot_describe`, `godot_info`, `godot_screenshot`, `godot_execute`, `godot_status`.

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
| `godot_call` | Call any method |
| `godot_list_methods` | List methods by category (live from the connected editor) |
| `godot_describe` | Full schema (params, types, annotations) for one or more methods |
| `godot_info` | Project info |
| `godot_screenshot` | Editor screenshot in PNG |
| `godot_execute` | Run GDScript |
| `godot_status` | Check connection |
| `godot_assets` | Search/preview/import CC0 assets (Poly Haven, ambientCG) |

> **`godot_assets`** makes outbound network requests to `polyhaven.com` and
> `ambientcg.com`. `import` writes files under
> `<project>/assets/<provider>/<id>/` (path learned via `get_project_info`)
> and then triggers a project rescan. CC0 sources only (public domain, no
> attribution legally required); a `NOTICE.txt` is written next to each
> imported asset regardless.

> **Node paths**: `parent_path` and `node_path` parameters of `godot_call`
> (e.g. `add_node`, `update_property`, `delete_node`) are **always relative to
> the root of the currently edited scene** (`"."` = scene root). Absolute
> Godot paths (`"/root"`, `"../..."`) are rejected — they would target the
> editor's internal tree instead of the scene.
>
> **Session handles**: any `node_path` parameter also accepts a handle (an
> `"@id:<n>"` string, returned as `"handle"` by `get_scene_tree`, `add_node`,
> `rename_node`, etc.) instead of a path. A handle keeps addressing the same
> node across a rename or reparent, where a path would break — useful for
> chaining several calls against the node you just created/modified. A
> handle goes stale when the scene is reloaded/reopened; call
> `get_scene_tree` again for a fresh one.
>
> **`godot_screenshot`** requires an editor with active rendering: it does not
> work in `--headless` mode ("Could not get image from viewport" error).

## MCP resources and prompts

Besides tools, the server exposes project state as **resources** (free in
tokens until actually read, unlike tools): `godot://scene/current`,
`godot://project/info`, `godot://project/settings`, `godot://logs/recent`,
and the template `godot://class/{name}` (ClassDB reflection, cached for 5
minutes — engine classes don't change mid-session).

Four reusable **prompts** guide the workflows this server was built for:
`blockout-3d-level`, `diagnose-crash`, `audit-scene-perf`, `asset-strategy`.

`godot_assets {action: "import"}` sends `notifications/progress` updates if
the client supplies a `progressToken` — the download can take a while on a
slow connection.

## Development

```bash
npm test           # unit tests (vitest): WS framing, JSON-RPC dispatch
npm run test:godot # headless GDScript tests (needs `godot`/`godot4` on PATH or GODOT_BIN)
```

## Structure

```
godot-mcp/
├── plugin/              ← Godot plugin (copy to your project)
├── src/index.ts         ← MCP server (Node.js)
├── src/assets/          ← CC0 asset sourcing (Poly Haven, ambientCG)
├── test/                ← vitest suite + headless GDScript fixture project
├── package.json
├── tsconfig.json
├── README.md
└── LICENSE              ← MIT
```

## License

MIT

This Godot plugin is derived from [godot-mcp-pro](https://github.com/youichi-uda/godot-mcp-pro) (Youichi Uda, MIT).

[🇫🇷 Français](#fr) · [🇬🇧 English](#en)

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Godot 4.3+](https://img.shields.io/badge/Godot-4.3%2B-478cbf.svg)
![Node >=18](https://img.shields.io/badge/Node-%3E%3D18-339933.svg)
![Zero runtime deps](https://img.shields.io/badge/runtime%20deps-MCP%20SDK%20only-informational.svg)

---

# <a id="fr"></a>godot-mcp

**Donnez à votre assistant IA les mains sur l'éditeur Godot — sans lui donner 100 outils à trier.**

```
Assistant IA <---stdio/MCP---> godot-mcp <---WebSocket:6505---> Plugin Godot
```

## Pourquoi celui-ci

La plupart des serveurs MCP Godot exposent chaque méthode de l'addon comme
un *tool* MCP séparé — 50, 80, parfois plus de 100 entrées dans le catalogue
que le modèle doit lire et trier avant chaque appel. Plus la surface est
large, moins un LLM choisit le bon outil de façon fiable, et plus chaque
requête coûte cher en tokens rien que pour décrire les outils disponibles.

godot-mcp prend le pari inverse : **10 outils**, dont un seul (`godot_call`)
donne accès à un catalogue de **210 méthodes** réparties en ~25 catégories
(scène, nodes, 3D, physique, animation, shaders, tilemap, particules, audio,
navigation, export Android, tests…), découvert **en direct** auprès de
l'éditeur connecté plutôt que figé dans ce dépôt. Le modèle demande le
schéma dont il a besoin (`godot_describe`) au lieu de tout charger d'un
coup. Résultat mesuré (`npm run token-cost`) : **~1460 tokens** pour toute
la surface d'outils.

Le reste tient en une phrase : **zéro dépendance runtime** en dehors du SDK
MCP, **aucun service externe**, le plugin Godot est un simple client
WebSocket — vous savez exactement ce qui tourne et où.

### Ce qui distingue ce pont d'un simple exécuteur de commandes

- **Garde-fous, pas juste des fonctions.** Les opérations destructrices
  (suppression de fichier, édition de script, code arbitraire) exigent
  `confirm: true` ; les éditions de script portent un garde optimiste par
  SHA-256 pour ne pas écraser silencieusement un changement fait entre-temps
  dans l'éditeur ; les mutations de scène passent par
  `EditorUndoRedoManager` — un Ctrl-Z suffit toujours à annuler.
- **Multi-éditeur.** Plusieurs projets Godot peuvent se connecter en même
  temps ; `godot_status {"select": "..."}` épingle celui qui doit recevoir
  les appels au lieu de tomber sur le premier connecté par hasard.
- **Les opérations longues ne timeout plus.** `godot_call {"async": true}`
  rend la main immédiatement avec un `job_id` à relire via `godot_job` —
  un stress test de 60s ne meurt plus au bout de 30.
- **Compatibilité de version fine.** Chaque méthode déclare la version
  Godot minimale qu'elle requiert ; sur un moteur plus ancien, seules ces
  méthodes-là disparaissent du catalogue au lieu de faire échouer tout
  l'addon.
- **Capture d'erreurs structurée**, pas du scraping d'UI : les erreurs
  runtime sont interceptées via le signal `debug_data` du debugger Godot.
- **Playtesting déterministe** : seed RNG fixée, tick de simulation fixe,
  snapshots d'état, avance frame-par-frame (`step_frames`) ou jusqu'à
  condition (`wait_for_condition`) — pour reproduire un bug plutôt que le
  chasser à l'aveugle.
- **Perception 3D** : modes de rendu debug (wireframe, overdraw, éclairage
  seul…) sur les captures d'écran, détection d'objets qui se chevauchent ou
  flottent, test de frustum caméra, couverture des lumières — un lint
  spatial pour repérer ce qu'un screenshot seul ne montre pas.
- **Assets CC0 intégrés** : recherche, prévisualisation et import direct
  depuis Poly Haven et ambientCG, sans quitter la conversation.

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
| `godot_call` | Appelle n'importe quelle méthode du catalogue (`async: true` pour les appels longs) |
| `godot_list_methods` | Liste les méthodes par catégorie (en direct depuis l'éditeur connecté) |
| `godot_describe` | Schéma complet (paramètres, types, annotations) d'une ou plusieurs méthodes |
| `godot_info` | Infos projet |
| `godot_screenshot` | Capture éditeur en PNG |
| `godot_execute` | Exécute du GDScript |
| `godot_status` | Vérifie la connexion, épingle un éditeur (`select`) si plusieurs sont connectés |
| `godot_job` | Relit le résultat d'un appel `async: true` |
| `godot_doctor` | Diagnostic complet : port, connexion, auth, contrat addon/serveur, binaire Godot |
| `godot_assets` | Recherche/prévisualise/importe des assets CC0 (Poly Haven, ambientCG) |

> **Confirmation obligatoire (`confirm: true`)** : les méthodes qui écrivent
> ou suppriment un fichier sur disque, modifient `project.godot`, ou exécutent
> du code arbitraire dans le process éditeur/jeu (`create_scene`,
> `delete_scene`, `edit_script`, `execute_editor_script`, `set_project_setting`,
> etc.) refusent l'appel avec l'erreur `-32009` tant que `params.confirm` n'est
> pas `true`. `godot_describe` liste ce paramètre dans le schéma de chaque
> méthode concernée. Les mutations de la **scène éditée** (ajout/suppression
> de nodes, changement de propriétés, CSG, scatter…) ne sont **pas** gatées :
> elles passent par `EditorUndoRedoManager` et un simple Ctrl-Z suffit à les
> annuler.
>
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
npm test           # tests unitaires (vitest), y compris le contract-check addon/serveur
npm run contract    # contract-check seul : get_commands()/get_command_schemas() alignés, modules enregistrés
npm run test:godot  # tests GDScript en --headless (nécessite `godot`/`godot4` sur le PATH ou GODOT_BIN)
npm run token-cost  # mesure le poids en tokens de la surface d'outils (et le contrefactuel si un éditeur est connecté)
```

## Licence

MIT

Ce plugin Godot dérive de [godot-mcp-pro](https://github.com/youichi-uda/godot-mcp-pro) (Youichi Uda, MIT).

---

# <a id="en"></a>godot-mcp

**Give your AI assistant real control of the Godot editor — without handing it 100 tools to sort through.**

```
AI Assistant <---stdio/MCP---> godot-mcp <---WebSocket:6505---> Godot Plugin
```

## Why this one

Most Godot MCP servers expose every addon method as its own MCP tool — 50,
80, sometimes 100+ entries the model has to read and sort through before
every single call. The bigger that surface gets, the less reliably an LLM
picks the right tool, and the more tokens get burned on tool descriptions
before the conversation even starts.

godot-mcp takes the opposite bet: **10 tools**, one of which (`godot_call`)
opens onto a catalog of **210 methods** across ~25 categories (scene,
nodes, 3D, physics, animation, shaders, tilemaps, particles, audio,
navigation, Android export, testing…), discovered **live** from the
connected editor instead of hardcoded in this repo. The model asks for the
schema it actually needs (`godot_describe`) instead of loading everything
up front. Measured result (`npm run token-cost`): **~1460 tokens** for the
whole tool surface.

Everything else fits in one sentence: **zero runtime dependencies** beyond
the MCP SDK, **no external services**, the Godot plugin is a plain
WebSocket client — you know exactly what's running and where.

### What sets this apart from a plain command runner

- **Guardrails, not just functions.** Destructive operations (deleting a
  file, editing a script, running arbitrary code) require `confirm: true`;
  script edits carry an optimistic SHA-256 guard so they can't silently
  clobber a change made in the editor in the meantime; scene mutations go
  through `EditorUndoRedoManager` — a plain Ctrl-Z always undoes them.
- **Multi-editor aware.** Several Godot projects can stay connected at
  once; `godot_status {"select": "..."}` pins which one receives calls
  instead of falling back to whichever connected first.
- **Long operations stop timing out.** `godot_call {"async": true}` returns
  a `job_id` immediately, polled via `godot_job` — a 60-second stress test
  no longer dies at the 30-second mark.
- **Fine-grained version compatibility.** Every method declares the
  minimum Godot version it needs; on an older engine, only those specific
  methods drop out of the catalog instead of the whole addon failing to
  load.
- **Structured error capture**, not UI scraping: runtime errors are
  intercepted through Godot's debugger `debug_data` signal.
- **Deterministic playtesting**: fixed RNG seed, fixed simulation tick,
  state snapshots, frame-by-frame stepping (`step_frames`) or stepping
  until a condition holds (`wait_for_condition`) — reproduce a bug instead
  of hunting it blind.
- **3D perception**: debug render modes (wireframe, overdraw, lighting
  only…) on screenshots, overlapping/floating object detection, camera
  frustum testing, light coverage — a spatial lint for what a single
  screenshot won't show you.
- **Built-in CC0 assets**: search, preview, and import directly from Poly
  Haven and ambientCG without leaving the conversation.

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
| `godot_call` | Call any method in the catalog (`async: true` for long-running calls) |
| `godot_list_methods` | List methods by category (live from the connected editor) |
| `godot_describe` | Full schema (params, types, annotations) for one or more methods |
| `godot_info` | Project info |
| `godot_screenshot` | Editor screenshot in PNG |
| `godot_execute` | Run GDScript |
| `godot_status` | Check connection, pin an editor (`select`) when several are connected |
| `godot_job` | Poll the result of an `async: true` call |
| `godot_doctor` | End-to-end diagnostic: port, connection, auth, addon/server contract, Godot binary |
| `godot_assets` | Search/preview/import CC0 assets (Poly Haven, ambientCG) |

> **Confirmation required (`confirm: true`)**: methods that write to or
> delete a file on disk, modify `project.godot`, or run arbitrary code in the
> editor/game process (`create_scene`, `delete_scene`, `edit_script`,
> `execute_editor_script`, `set_project_setting`, etc.) refuse the call with a
> `-32009` error until `params.confirm` is `true`. `godot_describe` lists this
> parameter in the schema of every gated method. Mutations to the **edited
> scene** (adding/removing nodes, property changes, CSG, scatter…) are **not**
> gated: they go through `EditorUndoRedoManager`, so a plain Ctrl-Z undoes
> them.
>
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
npm test           # unit tests (vitest), including the addon/server contract-check
npm run contract    # contract-check alone: get_commands()/get_command_schemas() agree, every module registered
npm run test:godot  # headless GDScript tests (needs `godot`/`godot4` on PATH or GODOT_BIN)
npm run token-cost  # measures the tool surface's token weight (and the counterfactual if an editor is connected)
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

import { writeFile } from "node:fs/promises";
import path from "node:path";
import { searchPolyHaven, getPolyHavenThumbnail, importPolyHaven, type ImportedFile } from "./polyhaven.js";
import { searchAmbientCG, getAmbientCGThumbnail, importAmbientCG } from "./ambientcg.js";

export type AssetProvider = "polyhaven" | "ambientcg";

export interface AssetSearchResult {
  provider: AssetProvider;
  id: string;
  name: string;
  type: string;
  license: string;
  tags: string[];
}

export async function searchAssets(
  query: string,
  opts: { provider?: AssetProvider; type?: string; limit?: number } = {}
): Promise<AssetSearchResult[]> {
  const limit = opts.limit ?? 20;
  const results: AssetSearchResult[] = [];

  if (!opts.provider || opts.provider === "polyhaven") {
    const found = await searchPolyHaven(query, opts.type, limit).catch((err) => {
      console.error(`godot-mcp: Poly Haven search failed: ${(err as Error).message}`);
      return [];
    });
    for (const a of found) results.push({ provider: "polyhaven", id: a.id, name: a.name, type: a.type, license: "CC0", tags: a.tags });
  }
  if (!opts.provider || opts.provider === "ambientcg") {
    const found = await searchAmbientCG(query, opts.type, limit).catch((err) => {
      console.error(`godot-mcp: ambientCG search failed: ${(err as Error).message}`);
      return [];
    });
    for (const a of found) results.push({ provider: "ambientcg", id: a.id, name: a.name, type: a.type, license: "CC0", tags: a.tags });
  }

  return results.slice(0, limit);
}

export async function getAssetThumbnail(provider: AssetProvider, id: string): Promise<Buffer> {
  if (provider === "polyhaven") return getPolyHavenThumbnail(id);
  if (provider === "ambientcg") return getAmbientCGThumbnail(id);
  throw new Error(`Unknown asset provider '${provider}'`);
}

export interface AssetImportResult {
  files: ImportedFile[];
  noticePath: string;
  destDir: string;
}

// A caller-controlled id becomes a directory name under the project root —
// strip anything that isn't a safe path segment character so it can't
// escape assets/<provider>/ (e.g. via "../../autoload").
function slugify(id: string): string {
  return id.replace(/[^a-zA-Z0-9_.-]/g, "_");
}

export async function importAsset(
  provider: AssetProvider,
  id: string,
  projectPath: string,
  opts: { resolution?: string; format?: string } = {}
): Promise<AssetImportResult> {
  const destDir = path.join(projectPath, "assets", provider, slugify(id));

  let files: ImportedFile[];
  let sourceUrl: string;
  if (provider === "polyhaven") {
    files = await importPolyHaven(id, destDir, opts);
    sourceUrl = `https://polyhaven.com/a/${id}`;
  } else if (provider === "ambientcg") {
    files = await importAmbientCG(id, destDir, opts.resolution ?? "2K");
    sourceUrl = `https://ambientcg.com/view?id=${id}`;
  } else {
    throw new Error(`Unknown asset provider '${provider}'`);
  }

  if (files.length === 0) {
    throw new Error(
      `No files were downloaded for ${provider}/${id} — the asset id may be wrong, or the requested ` +
      `resolution/format doesn't exist for it.`
    );
  }

  const noticePath = path.join(destDir, "NOTICE.txt");
  await writeFile(
    noticePath,
    [
      `Source: ${sourceUrl}`,
      `Provider: ${provider}`,
      `Asset ID: ${id}`,
      `License: CC0 1.0 Universal (public domain) — no attribution legally required.`,
      `Imported by godot-mcp on ${new Date().toISOString()}`,
      "",
    ].join("\n")
  );

  return { files, noticePath, destDir };
}

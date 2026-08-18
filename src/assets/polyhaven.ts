import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fetchBuffer, fetchJson } from "./http.js";

// Poly Haven's API (api.polyhaven.com) has no auth and no rate-limit header
// contract we need to respect beyond being a reasonable citizen. Everything
// on the site is CC0 (public domain). Unlike ambientCG, texture and model
// downloads are NOT zipped — /files/{id} hands back a direct URL per
// map/resolution/format (and, for glTF models, a manifest of dependent
// files each with their own direct URL) — verified against the live API
// before writing this.
const API = "https://api.polyhaven.com";
const CDN_THUMB = "https://cdn.polyhaven.com/asset_img/thumbs";

export interface PolyHavenAsset {
  id: string;
  name: string;
  type: "hdris" | "textures" | "models";
  thumbnailUrl: string;
  tags: string[];
}

interface PolyHavenListEntry {
  name?: string;
  tags?: string[];
  categories?: string[];
  thumbnail_url?: string;
}

export async function searchPolyHaven(query: string, type?: string, limit = 20): Promise<PolyHavenAsset[]> {
  const types = (type ? [type] : ["hdris", "textures", "models"]) as PolyHavenAsset["type"][];
  const q = query.trim().toLowerCase();
  const results: PolyHavenAsset[] = [];

  for (const t of types) {
    if (results.length >= limit) break;
    let data: Record<string, PolyHavenListEntry>;
    try {
      data = await fetchJson(`${API}/assets?t=${encodeURIComponent(t)}`);
    } catch {
      continue; // an unknown/misspelled type just yields no results for it
    }
    for (const [id, asset] of Object.entries(data)) {
      const name = asset.name ?? id;
      const tags = asset.tags ?? [];
      const haystack = `${id} ${name} ${tags.join(" ")} ${(asset.categories ?? []).join(" ")}`.toLowerCase();
      if (!q || haystack.includes(q)) {
        results.push({ id, name, type: t, thumbnailUrl: asset.thumbnail_url ?? thumbnailUrl(id), tags });
      }
      if (results.length >= limit) break;
    }
  }
  return results.slice(0, limit);
}

function thumbnailUrl(id: string): string {
  return `${CDN_THUMB}/${id}.png?width=256&height=256`;
}

export async function getPolyHavenThumbnail(id: string): Promise<Buffer> {
  return fetchBuffer(thumbnailUrl(id));
}

interface PolyHavenFileEntry {
  url: string;
  size: number;
  md5: string;
  include?: Record<string, { url: string; size: number; md5: string }>;
}

type PolyHavenFiles = Record<string, Record<string, Record<string, PolyHavenFileEntry>>>;

export interface ImportedFile {
  path: string;
  bytes: number;
}

export async function importPolyHaven(
  id: string,
  destDir: string,
  opts: { resolution?: string; format?: string } = {}
): Promise<ImportedFile[]> {
  const files = await fetchJson<PolyHavenFiles>(`${API}/files/${encodeURIComponent(id)}`);
  const resolution = opts.resolution ?? pickDefaultResolution(files);
  const written: ImportedFile[] = [];

  for (const [mapType, byRes] of Object.entries(files)) {
    const mt = mapType.toLowerCase();
    // Blender/MaterialX source files aren't directly usable inside Godot and
    // would otherwise dominate the download for no benefit.
    if (mt === "blend" || mt === "mtlx") continue;

    const atRes = byRes[resolution] ?? byRes[Object.keys(byRes)[0]];
    if (!atRes) continue;
    const format = opts.format && atRes[opts.format] ? opts.format : pickDefaultFormat(mt, atRes);
    const entry = atRes[format];
    if (!entry) continue;

    if (entry.include) {
      // glTF-style manifest: a primary file plus dependent files (textures,
      // .bin), each independently downloadable — no zip involved.
      await downloadTo(entry.url, path.join(destDir, `${id}.${format}`), written);
      for (const [relName, dep] of Object.entries(entry.include)) {
        await downloadTo(dep.url, path.join(destDir, relName), written);
      }
    } else {
      await downloadTo(entry.url, path.join(destDir, `${id}_${mt}_${resolution}.${format}`), written);
    }
  }

  return written;
}

async function downloadTo(url: string, destPath: string, written: ImportedFile[]): Promise<void> {
  const buf = await fetchBuffer(url);
  await mkdir(path.dirname(destPath), { recursive: true });
  await writeFile(destPath, buf);
  written.push({ path: destPath, bytes: buf.length });
}

export function pickDefaultResolution(files: PolyHavenFiles): string {
  const allRes = new Set<string>();
  for (const byRes of Object.values(files)) {
    for (const res of Object.keys(byRes)) allRes.add(res);
  }
  // Smallest first: a caller who didn't ask for a specific resolution is
  // better served by a fast, light default than an 8k texture they didn't want.
  for (const pref of ["1k", "2k", "4k", "8k"]) if (allRes.has(pref)) return pref;
  return [...allRes][0] ?? "1k";
}

export function pickDefaultFormat(mapType: string, atRes: Record<string, PolyHavenFileEntry>): string {
  if (mapType === "gltf") return "gltf";
  for (const pref of ["jpg", "png", "hdr", "exr"]) if (atRes[pref]) return pref;
  return Object.keys(atRes)[0];
}

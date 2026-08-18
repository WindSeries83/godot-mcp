import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fetchBuffer, fetchJson } from "./http.js";
import { extractZip } from "./zip.js";
import type { ImportedFile } from "./polyhaven.js";

// ambientCG (ambientcg.com) — all assets CC0. Unlike Poly Haven, downloads
// are zip bundles (verified against the live API: downloadFolders.default.
// downloadFiletypeCategories.zip.downloads[].downloadLink), so importing
// here goes through zip.ts.
const API = "https://ambientcg.com/api/v2/full_json";

export interface AmbientCGAsset {
  id: string;
  name: string;
  type: string;
  thumbnailUrl: string;
  tags: string[];
}

interface AmbientCGRawAsset {
  assetId: string;
  displayName?: string;
  dataType?: string;
  assetType?: string;
  tags?: string[];
  previewImage?: Record<string, string>;
  downloadFolders?: {
    default?: {
      downloadFiletypeCategories?: {
        zip?: { downloads?: { downloadLink: string; fileName?: string; attribute?: string }[] };
      };
    };
  };
}

function toAsset(a: AmbientCGRawAsset): AmbientCGAsset {
  return {
    id: a.assetId,
    name: a.displayName ?? a.assetId,
    type: a.dataType ?? a.assetType ?? "Material",
    thumbnailUrl: a.previewImage?.["256-PNG"] ?? "",
    tags: a.tags ?? [],
  };
}

export async function searchAmbientCG(query: string, category?: string, limit = 20): Promise<AmbientCGAsset[]> {
  const params = new URLSearchParams({ limit: String(limit), include: "imageData" });
  if (query) params.set("q", query);
  if (category) params.set("type", category);
  const data = await fetchJson<{ foundAssets?: AmbientCGRawAsset[] }>(`${API}?${params}`);
  return (data.foundAssets ?? []).map(toAsset);
}

interface AmbientCGDetail extends AmbientCGAsset {
  downloadUrl: string;
  resolution: string;
}

// ambientCG's "id" query param (distinct from the free-text "q" param, which
// tokenizes and would miss e.g. "Concrete034" against the display name
// "Concrete 034") does an exact assetId lookup — verified against the live
// API before writing this.
async function getAmbientCGDetail(id: string, resolution = "2K"): Promise<AmbientCGDetail> {
  const params = new URLSearchParams({ id, include: "downloadData,imageData" });
  const data = await fetchJson<{ foundAssets?: AmbientCGRawAsset[] }>(`${API}?${params}`);
  const asset = (data.foundAssets ?? [])[0];
  if (!asset) throw new Error(`ambientCG asset '${id}' not found`);

  const downloads = asset.downloadFolders?.default?.downloadFiletypeCategories?.zip?.downloads ?? [];
  const match =
    downloads.find((d) => d.attribute?.includes(resolution) || d.fileName?.includes(resolution)) ?? downloads[0];
  if (!match) throw new Error(`No zip download found for ambientCG asset '${id}'`);

  return { ...toAsset(asset), downloadUrl: match.downloadLink, resolution };
}

export async function getAmbientCGThumbnail(id: string): Promise<Buffer> {
  const detail = await getAmbientCGDetail(id);
  if (!detail.thumbnailUrl) throw new Error(`No thumbnail available for ambientCG asset '${id}'`);
  return fetchBuffer(detail.thumbnailUrl);
}

export async function importAmbientCG(id: string, destDir: string, resolution = "2K"): Promise<ImportedFile[]> {
  const detail = await getAmbientCGDetail(id, resolution);
  const buf = await fetchBuffer(detail.downloadUrl);
  const entries = extractZip(buf);

  const written: ImportedFile[] = [];
  for (const entry of entries) {
    const destPath = path.join(destDir, entry.name);
    await mkdir(path.dirname(destPath), { recursive: true });
    await writeFile(destPath, entry.data);
    written.push({ path: destPath, bytes: entry.data.length });
  }
  return written;
}

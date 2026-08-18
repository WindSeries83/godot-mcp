// Shared fetch helper for the asset-source providers. A single place to cap
// download size — an asset pack can legitimately be large, but nothing here
// should let a malformed/malicious response exhaust memory silently.
export const MAX_DOWNLOAD_BYTES = 300 * 1024 * 1024; // 300MB: generous for one asset, not for a runaway response

export async function fetchBuffer(url: string, maxBytes = MAX_DOWNLOAD_BYTES): Promise<Buffer> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch failed (HTTP ${res.status}): ${url}`);
  const len = res.headers.get("content-length");
  if (len && Number(len) > maxBytes) {
    throw new Error(`Refusing to download ${url}: declared size ${len} bytes exceeds the ${maxBytes}-byte limit`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length > maxBytes) {
    throw new Error(`Downloaded ${buf.length} bytes from ${url}, exceeding the ${maxBytes}-byte limit`);
  }
  return buf;
}

export async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch failed (HTTP ${res.status}): ${url}`);
  return res.json() as Promise<T>;
}

import { inflateRawSync } from "node:zlib";

// A minimal ZIP reader — just enough to pull files out of an ambientCG
// asset pack. Godot's own import pipeline and every other dependency in
// this repo is deliberately dependency-free (see package.json: the only
// runtime dependency is the MCP SDK itself), so this avoids pulling in a
// zip library for what is, structurally, a bounded and well-documented
// binary format: parse the End Of Central Directory record, walk the
// Central Directory it points to, and inflate each entry's Local File
// Header. No ZIP64 support (not needed for texture/material packs), no
// encryption, no multi-disk archives.

export interface ZipEntry {
  name: string;
  data: Buffer;
}

const EOCD_SIG = 0x06054b50;
const CENTRAL_SIG = 0x02014b50;
const LOCAL_SIG = 0x04034b50;

export function extractZip(buf: Buffer): ZipEntry[] {
  const eocdOffset = findEOCD(buf);
  if (eocdOffset < 0) throw new Error("Not a valid ZIP file (no End Of Central Directory record found)");

  const numEntries = buf.readUInt16LE(eocdOffset + 10);
  const cdOffset = buf.readUInt32LE(eocdOffset + 16);

  const entries: ZipEntry[] = [];
  let p = cdOffset;
  for (let i = 0; i < numEntries; i++) {
    if (buf.readUInt32LE(p) !== CENTRAL_SIG) {
      throw new Error(`Corrupt ZIP: expected central directory signature at entry ${i}`);
    }
    const compressionMethod = buf.readUInt16LE(p + 10);
    const compressedSize = buf.readUInt32LE(p + 20);
    const uncompressedSize = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const localHeaderOffset = buf.readUInt32LE(p + 42);
    const name = buf.toString("utf8", p + 46, p + 46 + nameLen);
    p += 46 + nameLen + extraLen + commentLen;

    // Directory entries have no content and end in "/" — nothing to extract.
    if (name.endsWith("/") && uncompressedSize === 0) continue;

    const data = readLocalEntry(buf, localHeaderOffset, compressionMethod, compressedSize);
    entries.push({ name, data });
  }
  return entries;
}

function readLocalEntry(buf: Buffer, offset: number, method: number, compressedSize: number): Buffer {
  if (buf.readUInt32LE(offset) !== LOCAL_SIG) {
    throw new Error("Corrupt ZIP: local file header signature mismatch");
  }
  const nameLen = buf.readUInt16LE(offset + 26);
  const extraLen = buf.readUInt16LE(offset + 28);
  const dataStart = offset + 30 + nameLen + extraLen;
  const raw = buf.subarray(dataStart, dataStart + compressedSize);
  if (method === 0) return Buffer.from(raw); // stored, no compression
  if (method === 8) return inflateRawSync(raw); // deflate
  throw new Error(`Unsupported ZIP compression method ${method} (only stored/deflate are supported)`);
}

function findEOCD(buf: Buffer): number {
  // The EOCD record is 22 bytes plus an optional comment up to 65535 bytes,
  // so it can't be further than that from the end of the file.
  const minPos = Math.max(0, buf.length - 22 - 65535);
  for (let i = buf.length - 22; i >= minPos; i--) {
    if (buf.readUInt32LE(i) === EOCD_SIG) return i;
  }
  return -1;
}

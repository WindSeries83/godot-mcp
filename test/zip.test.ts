import { describe, it, expect } from "vitest";
import { deflateRawSync } from "node:zlib";
import { extractZip } from "../src/assets/zip.js";

// extractZip doesn't verify CRC32, so these fixtures can use 0 there
// without needing a CRC32 implementation just for tests.
interface FixtureEntry {
  name: string;
  data: Buffer;
  method: 0 | 8; // stored | deflate
}

function buildZip(entries: FixtureEntry[]): Buffer {
  const localParts: Buffer[] = [];
  const centralParts: Buffer[] = [];
  const offsets: number[] = [];
  let offset = 0;

  for (const entry of entries) {
    offsets.push(offset);
    const nameBuf = Buffer.from(entry.name, "utf8");
    const payload = entry.method === 8 ? deflateRawSync(entry.data) : entry.data;

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4); // version needed
    local.writeUInt16LE(0, 6); // flags
    local.writeUInt16LE(entry.method, 8);
    local.writeUInt16LE(0, 10); // mod time
    local.writeUInt16LE(0, 12); // mod date
    local.writeUInt32LE(0, 14); // crc32 (unchecked by our reader)
    local.writeUInt32LE(payload.length, 18); // compressed size
    local.writeUInt32LE(entry.data.length, 22); // uncompressed size
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28); // extra field length

    const localEntry = Buffer.concat([local, nameBuf, payload]);
    localParts.push(localEntry);
    offset += localEntry.length;
  }

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    const nameBuf = Buffer.from(entry.name, "utf8");
    const payload = entry.method === 8 ? deflateRawSync(entry.data) : entry.data;

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4); // version made by
    central.writeUInt16LE(20, 6); // version needed
    central.writeUInt16LE(0, 8); // flags
    central.writeUInt16LE(entry.method, 10);
    central.writeUInt16LE(0, 12); // mod time
    central.writeUInt16LE(0, 14); // mod date
    central.writeUInt32LE(0, 16); // crc32
    central.writeUInt32LE(payload.length, 20); // compressed size
    central.writeUInt32LE(entry.data.length, 24); // uncompressed size
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt16LE(0, 30); // extra field length
    central.writeUInt16LE(0, 32); // comment length
    central.writeUInt16LE(0, 34); // disk number start
    central.writeUInt16LE(0, 36); // internal attrs
    central.writeUInt32LE(0, 38); // external attrs
    central.writeUInt32LE(offsets[i], 42); // local header offset

    centralParts.push(Buffer.concat([central, nameBuf]));
  }

  const localData = Buffer.concat(localParts);
  const centralData = Buffer.concat(centralParts);

  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4); // disk number
  eocd.writeUInt16LE(0, 6); // disk with central dir
  eocd.writeUInt16LE(entries.length, 8); // entries on this disk
  eocd.writeUInt16LE(entries.length, 10); // total entries
  eocd.writeUInt32LE(centralData.length, 12); // central dir size
  eocd.writeUInt32LE(localData.length, 16); // central dir offset
  eocd.writeUInt16LE(0, 20); // comment length

  return Buffer.concat([localData, centralData, eocd]);
}

describe("extractZip", () => {
  it("reads a single stored (uncompressed) entry", () => {
    const zip = buildZip([{ name: "hello.txt", data: Buffer.from("hello world"), method: 0 }]);
    const entries = extractZip(zip);
    expect(entries).toHaveLength(1);
    expect(entries[0].name).toBe("hello.txt");
    expect(entries[0].data.toString("utf8")).toBe("hello world");
  });

  it("reads a single deflated entry", () => {
    const text = "the quick brown fox jumps over the lazy dog ".repeat(20);
    const zip = buildZip([{ name: "material/diffuse.txt", data: Buffer.from(text), method: 8 }]);
    const entries = extractZip(zip);
    expect(entries).toHaveLength(1);
    expect(entries[0].name).toBe("material/diffuse.txt");
    expect(entries[0].data.toString("utf8")).toBe(text);
  });

  it("reads multiple mixed-method entries in order", () => {
    const zip = buildZip([
      { name: "a.txt", data: Buffer.from("aaa"), method: 0 },
      { name: "dir/b.txt", data: Buffer.from("bbb".repeat(50)), method: 8 },
      { name: "c.txt", data: Buffer.from("ccc"), method: 0 },
    ]);
    const entries = extractZip(zip);
    expect(entries.map((e) => e.name)).toEqual(["a.txt", "dir/b.txt", "c.txt"]);
    expect(entries[0].data.toString("utf8")).toBe("aaa");
    expect(entries[1].data.toString("utf8")).toBe("bbb".repeat(50));
    expect(entries[2].data.toString("utf8")).toBe("ccc");
  });

  it("skips directory entries", () => {
    const zip = buildZip([
      { name: "textures/", data: Buffer.alloc(0), method: 0 },
      { name: "textures/diffuse.jpg", data: Buffer.from("fakejpgdata"), method: 0 },
    ]);
    const entries = extractZip(zip);
    expect(entries).toHaveLength(1);
    expect(entries[0].name).toBe("textures/diffuse.jpg");
  });

  it("throws a clear error on non-ZIP data instead of reading garbage", () => {
    expect(() => extractZip(Buffer.from("not a zip file at all"))).toThrow(/End Of Central Directory/);
  });
});

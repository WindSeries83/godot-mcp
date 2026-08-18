import { describe, it, expect } from "vitest";
import { Duplex } from "node:stream";
import { wsSend, wsAccept, decodeFrame } from "../src/index.js";

// Captures whatever wsSend() writes so we can inspect the raw frame bytes.
function captureSocket(): { socket: Duplex; written: () => Buffer } {
  const chunks: Buffer[] = [];
  const socket = new Duplex({
    write(chunk, _enc, cb) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      cb();
    },
    read() {},
  });
  return { socket, written: () => Buffer.concat(chunks) };
}

// Masks a text payload the way a real WebSocket client (the Godot addon) is
// required to: client->server frames must be masked per RFC 6455.
function encodeClientFrame(text: string): Buffer {
  const payload = Buffer.from(text, "utf8");
  const mask = Buffer.from([0x12, 0x34, 0x56, 0x78]);
  const masked = Buffer.alloc(payload.length);
  for (let i = 0; i < payload.length; i++) masked[i] = payload[i] ^ mask[i % 4];

  let header: Buffer;
  if (payload.length < 126) {
    header = Buffer.from([0x81, 0x80 | payload.length]);
  } else if (payload.length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81; header[1] = 0x80 | 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81; header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(payload.length), 2);
  }
  return Buffer.concat([header, mask, masked]);
}

describe("wsAccept", () => {
  it("computes the RFC 6455 handshake accept key", () => {
    // Value from the RFC 6455 example handshake.
    expect(wsAccept("dGhlIHNhbXBsZSBub25jZQ==")).toBe("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
  });
});

describe("wsSend framing", () => {
  it("uses the short length form under 126 bytes", () => {
    const { socket, written } = captureSocket();
    wsSend(socket, "hi");
    const buf = written();
    expect(buf[0]).toBe(0x81);
    expect(buf[1]).toBe(2); // no 0x7E marker
    expect(buf.subarray(2).toString("utf8")).toBe("hi");
  });

  it("uses the 16-bit extended length marker between 126 and 65535 bytes", () => {
    // Regression guard for the documented Godot 4.7 WebSocketPeer quirk:
    // it must be 0x7E + a real u16be length, not folded into the first byte.
    const { socket, written } = captureSocket();
    const text = "x".repeat(200);
    wsSend(socket, text);
    const buf = written();
    expect(buf[0]).toBe(0x81);
    expect(buf[1]).toBe(126);
    expect(buf.readUInt16BE(2)).toBe(200);
    expect(buf.subarray(4).toString("utf8")).toBe(text);
  });

  it("uses the 64-bit extended length marker at 65536 bytes and above", () => {
    const { socket, written } = captureSocket();
    const text = "y".repeat(70_000);
    wsSend(socket, text);
    const buf = written();
    expect(buf[0]).toBe(0x81);
    expect(buf[1]).toBe(127);
    expect(Number(buf.readBigUInt64BE(2))).toBe(70_000);
  });
});

describe("decodeFrame", () => {
  it("round-trips a short masked client frame", () => {
    const frame = encodeClientFrame("hello");
    const decoded = decodeFrame(frame);
    expect(decoded).not.toBeNull();
    expect(decoded!.opcode).toBe(0x1);
    expect(decoded!.payload.toString("utf8")).toBe("hello");
    expect(decoded!.total).toBe(frame.length);
  });

  it("round-trips a masked client frame using the 16-bit length marker", () => {
    const text = "z".repeat(500);
    const frame = encodeClientFrame(text);
    const decoded = decodeFrame(frame);
    expect(decoded!.payload.toString("utf8")).toBe(text);
    expect(decoded!.total).toBe(frame.length);
  });

  it("returns null on a truncated frame instead of throwing", () => {
    const frame = encodeClientFrame("hello world");
    expect(decodeFrame(frame.subarray(0, 3))).toBeNull();
  });

  it("leaves the correct remainder so two concatenated frames both decode", () => {
    const a = encodeClientFrame("first");
    const b = encodeClientFrame("second");
    const combined = Buffer.concat([a, b]);
    const first = decodeFrame(combined);
    expect(first!.payload.toString("utf8")).toBe("first");
    const rest = combined.subarray(first!.total);
    const second = decodeFrame(rest);
    expect(second!.payload.toString("utf8")).toBe("second");
  });
});

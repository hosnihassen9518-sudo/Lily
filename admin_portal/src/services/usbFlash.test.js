import { createHash } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import { closeBoard, findIdentity, probeBoard, validatePackage, verifyResume, writeFirmware } from "./usbFlash";

const flashSize = 16 * 1024 * 1024;
const serial = "LILY-A1B2C3D4E5F60708";
const digest = (bytes, kind = "sha256") => createHash(kind).update(bytes).digest("hex");
const erased = (size) => new Uint8Array(size).fill(255);
const encoder = new TextEncoder();

function appImage() {
  const image = new Uint8Array(128);
  const header = new DataView(image.buffer);
  image[0] = 0xe9;
  image[1] = 1;
  image[12] = 9;
  header.setUint32(24, 0x3c000020, true);
  header.setUint32(28, 96, true);
  image.set(encoder.encode(serial), 42);
  return image;
}

function partitionTable() {
  const table = erased(4096);
  const view = new DataView(table.buffer);
  for (const [index, [type, subtype, address, size]] of [[1, 0, 0xe000, 0x2000], [0, 0x10, 0x10000, 0x300000], [0, 0x11, 0x310000, 0x300000]].entries()) {
    const offset = index * 32;
    view.setUint16(offset, 0x50aa, true);
    table[offset + 2] = type;
    table[offset + 3] = subtype;
    view.setUint32(offset + 4, address, true);
    view.setUint32(offset + 8, size, true);
  }
  return table;
}

function loaderFor(flash) {
  return {
    chip: {
      CHIP_NAME: "ESP32-S3",
      readMac: async () => "11:22:33:44:55:66",
      getChipFeatures: async () => ["Embedded PSRAM 8MB (AP_3v3)"],
    },
    detectFlashSize: async () => "16MB",
    flashSizeBytes: () => flash.length,
    flashMd5sum: async (address, size) => digest(flash.subarray(address, address + size), "md5"),
    readFlash: async (address, size) => flash.slice(address, address + size),
  };
}

const segment = (address, data) => ({ address, data_base64: Buffer.from(data).toString("base64"), sha256: digest(data) });

describe("USB flash guards", () => {
  it("reboots into normal firmware before releasing the serial port for a reset", async () => {
    const calls = [];
    await closeBoard({ port: { readable: true }, transport: {
      setDTR: async (value) => calls.push(["dtr", value]),
      setRTS: async (value) => calls.push(["rts", value]),
      disconnect: async () => calls.push(["disconnect"]),
    } });
    expect(calls).toEqual([["dtr", false], ["rts", true], ["rts", false], ["disconnect"]]);
  });
  it("recognizes a unique compiled serial and rejects ambiguous app identity", () => {
    expect(findIdentity(appImage())).toBe(serial);
    expect(findIdentity(encoder.encode(`${serial}\0LILY-1111111111111111\0`))).toBeNull();
  });

  it("distinguishes a fully erased board, unrecognized flash and an existing Lily", async () => {
    const flash = erased(flashSize);
    const loader = loaderFor(flash);
    await expect(probeBoard(loader, () => {})).resolves.toMatchObject({ kind: "blank" });
    flash[flash.length - 1] = 0;
    await expect(probeBoard(loader, () => {})).resolves.toMatchObject({ kind: "unknown" });
    const table = partitionTable();
    flash.set(table, 0x8000);
    flash.set(appImage(), 0x10000);
    await expect(probeBoard(loader, () => {})).resolves.toMatchObject({ kind: "existing", serial_number: serial, partition_sha256: digest(table) });
    flash[0x310000] = 0;
    await expect(probeBoard(loader, () => {})).resolves.toMatchObject({ kind: "unknown" });
  });

  it("validates the app-only update and refuses wrong identity, region, layout and checksum", async () => {
    const board = { chip: "ESP32-S3", flash_size: flashSize, serial_number: serial, partition_sha256: digest(partitionTable()), appSize: 0x300000 };
    const app = segment(0x10000, appImage());
    const pkg = { ...board, model_key: "lily_v2", segments: [app] };
    await expect(validatePackage(pkg, board, "keep", "lily_v2")).resolves.toHaveLength(1);
    for (const invalid of [
      { ...pkg, serial_number: "LILY-1111111111111111" },
      { ...pkg, partition_sha256: "bad" },
      { ...pkg, segments: [{ ...app, address: 0xe000 }] },
      { ...pkg, segments: [{ ...app, sha256: "bad" }] },
    ]) await expect(validatePackage(invalid, board, "keep", "lily_v2")).rejects.toThrow();
  });

  it("resumes an interrupted matching factory package and rejects unrelated flash bytes", async () => {
    const flash = erased(0x20000);
    const data = appImage();
    const files = [{ address: 0x10000, data }];
    flash.set(data.subarray(0, 32), 0x10000);
    const loader = loaderFor(flash);
    await expect(verifyResume(loader, flash.length, files)).resolves.toBeUndefined();
    flash[0x10000] = 0;
    await expect(verifyResume(loader, flash.length, files)).rejects.toThrow("differs");
    flash[0x9000] = 0;
    await expect(verifyResume(loader, flash.length, files)).rejects.toThrow("outside");
  });

  it("uses checksum verification without erasing unrelated regions", async () => {
    const loader = { writeFlash: vi.fn() };
    const files = [{ address: 0x10000, data: appImage() }];
    await writeFirmware({ loader }, files, () => {});
    expect(loader.writeFlash).toHaveBeenCalledWith(expect.objectContaining({ fileArray: files, eraseAll: false, flashMode: "keep" }));
    expect(loader.writeFlash.mock.calls[0][0].calculateMD5Hash(files[0].data)).toBe(digest(files[0].data, "md5"));
  });
});

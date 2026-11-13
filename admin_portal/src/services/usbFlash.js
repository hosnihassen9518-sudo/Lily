import { md5 } from "@noble/hashes/legacy.js";

const FLASH_SIZE = 16 * 1024 * 1024;
const PARTITION_ADDRESS = 0x8000;
const APP_ADDRESS = 0x10000;
const OTA_ADDRESS = 0xe000;
const OTA_SIZE = 0x2000;
const BOOT_APP0_SHA256 = "f94c5d786a7a8fab06ac5d10e33bf37711a6697636dc037559ea19cc410a17f0";
const SECTOR_SIZE = 4096;
const erasedSector = new Uint8Array(SECTOR_SIZE).fill(255);
const serialPattern = /^LILY-[0-9A-F]{16}$/;

const hex = (bytes) => Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
const md5Hex = (bytes) => hex(md5(bytes));
const sha256 = async (bytes) => hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));

function erasedMd5(length) {
  const hash = md5.create();
  while (length > 0) {
    const size = Math.min(length, erasedSector.length);
    hash.update(erasedSector.subarray(0, size));
    length -= size;
  }
  return hex(hash.digest());
}

// Read only app identity strings. Application bytes can contain private keys.
function scanIdentities(bytes) {
  const prefix = [76, 73, 76, 89, 45];
  const matches = new Set();
  for (let offset = 0; offset + 21 < bytes.length; offset++) {
    if (bytes[offset + 21] !== 0 || !prefix.every((byte, index) => bytes[offset + index] === byte)) continue;
    const serial = String.fromCharCode(...bytes.subarray(offset, offset + 21));
    if (serialPattern.test(serial)) matches.add(serial);
  }
  return matches;
}

export function findIdentity(bytes) {
  const matches = scanIdentities(bytes);
  return matches.size === 1 ? matches.values().next().value : null;
}

function partitions(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const entries = [];
  for (let cursor = 0; cursor + 32 <= bytes.length; cursor += 32) {
    const magic = view.getUint16(cursor, true);
    if (magic === 0xffff || magic === 0xebeb) break;
    if (magic !== 0x50aa) return [];
    const address = view.getUint32(cursor + 4, true);
    const size = view.getUint32(cursor + 8, true);
    if (!size || address % SECTOR_SIZE || size % SECTOR_SIZE || address + size > FLASH_SIZE) return [];
    entries.push({ type: bytes[cursor + 2], subtype: bytes[cursor + 3], address, size });
  }
  entries.sort((a, b) => a.address - b.address);
  return entries.some((entry, index) => index && entries[index - 1].address + entries[index - 1].size > entry.address)
    ? [] : entries;
}

async function readExact(loader, address, size) {
  const bytes = await loader.readFlash(address, size);
  if (bytes.length !== size) throw new Error("The ESP32 returned an incomplete flash read.");
  return bytes;
}

async function appIdentity(loader, app) {
  const header = await readExact(loader, app.address, 24);
  if (header[0] !== 0xe9 || header[1] < 1 || header[1] > 16 || header[12] !== 9 || header[13] !== 0) return null;
  const identities = new Set();
  let offset = 24;
  for (let segment = 0; segment < header[1]; segment++) {
    if (offset + 8 > app.size) return null;
    const info = await readExact(loader, app.address + offset, 8);
    const length = new DataView(info.buffer, info.byteOffset, 8).getUint32(4, true);
    offset += 8;
    if (length > app.size - offset) return null;
    // Only data mapped into DROM contains compiled factory serial strings.
    const loadAddress = new DataView(info.buffer, info.byteOffset, 8).getUint32(0, true);
    if (loadAddress >= 0x3c000000 && loadAddress < 0x3e000000) {
      const data = new Uint8Array(length);
      for (let chunk = 0; chunk < length; chunk += 65536) {
        const bytes = await readExact(loader, app.address + offset + chunk, Math.min(65536, length - chunk));
        data.set(bytes, chunk);
      }
      // Preserve boundary checks across all mapped segments rather than picking
      // the first serial string found in an image.
      for (const match of scanIdentities(data)) identities.add(match);
    }
    offset += length;
  }
  return identities.size === 1 ? identities.values().next().value : null;
}

export async function probeBoard(loader, progress) {
  const chip = loader.chip.CHIP_NAME;
  const mac = (await loader.chip.readMac(loader)).toLowerCase();
  const detectedSize = await loader.detectFlashSize();
  const flash_size = detectedSize ? loader.flashSizeBytes(detectedSize) : 0;
  if (chip !== "ESP32-S3" || flash_size !== FLASH_SIZE || !/^(?:[\da-f]{2}:){5}[\da-f]{2}$/.test(mac)) {
    throw new Error("This workflow supports ESP32-S3 boards with 16 MB of flash.");
  }
  const features = await loader.chip.getChipFeatures(loader);
  if (!features.some((feature) => feature.startsWith("Embedded PSRAM 8MB"))) {
    throw new Error("This workflow requires the ESP32-S3 N16R8 board with 8 MB of embedded PSRAM.");
  }
  const board = { chip, mac, flash_size };
  progress("Checking whether the board is blank…");
  if (await loader.flashMd5sum(0, flash_size) === erasedMd5(flash_size)) return { ...board, kind: "blank" };
  progress("Checking the partition layout and factory identity…");
  const table = await readExact(loader, PARTITION_ADDRESS, SECTOR_SIZE);
  const entries = partitions(table);
  const app = entries.find(({ type, subtype, address }) => type === 0 && subtype === 0x10 && address === APP_ADDRESS);
  if (!app || !entries.some(({ type, subtype, address, size }) => type === 1 && subtype === 0 && address === OTA_ADDRESS && size === OTA_SIZE)) {
    return { ...board, kind: "unknown" };
  }
  const ota = await readExact(loader, OTA_ADDRESS, OTA_SIZE);
  if (!ota.every((byte) => byte === 255) && await sha256(ota) !== BOOT_APP0_SHA256) {
    return { ...board, kind: "unknown" };
  }
  for (const alternate of entries.filter((entry) => entry.type === 0 && entry !== app)) {
    if (await loader.flashMd5sum(alternate.address, alternate.size) !== erasedMd5(alternate.size)) return { ...board, kind: "unknown" };
  }
  const serial_number = await appIdentity(loader, app);
  const layout = { partition_sha256: await sha256(table), appSize: app.size };
  if (!serial_number) return { ...board, ...layout, kind: "unknown" };
  return { ...board, ...layout, kind: "existing", serial_number };
}

export async function connectBoard(progress) {
  if (!globalThis.isSecureContext) throw new Error("Open the portal over HTTPS or localhost to access USB.");
  if (!navigator.serial) throw new Error("Open the portal in desktop Chrome or Edge to access USB.");
  const port = await navigator.serial.requestPort();
  progress("Connecting to ESP32 bootloader…");
  const { ESPLoader, Transport } = await import("esptool-js");
  const transport = new Transport(port);
  const terminal = { clean() {}, write() {}, writeLine() {} };
  const loader = new ESPLoader({ transport, terminal, baudrate: 460800 });
  const session = { port, loader, transport };
  try {
    await loader.main();
    return { ...session, board: await probeBoard(loader, progress) };
  } catch (error) {
    await closeBoard(session).catch(() => {});
    throw error;
  }
}

export async function closeBoard(session) {
  if (!session?.port.readable) return;
  try {
    await resetBoard(session.transport);
  } finally {
    await session.transport.disconnect();
  }
}

async function resetBoard(transport) {
  await transport.setDTR(false);
  await transport.setRTS(true);
  await new Promise((resolve) => setTimeout(resolve, 150));
  await transport.setRTS(false);
}

function decode(data) {
  if (typeof data !== "string" || data.length > FLASH_SIZE * 2) throw new Error("Invalid firmware segment.");
  return Uint8Array.from(atob(data), (char) => char.charCodeAt(0));
}

export async function validatePackage(pkg, board, mode, modelKey) {
  if (pkg.chip !== board.chip || pkg.flash_size !== board.flash_size || pkg.model_key !== modelKey || !serialPattern.test(pkg.serial_number)) {
    throw new Error("Firmware package does not match the selected model and board.");
  }
  if (mode !== "blank" && (pkg.serial_number !== board.serial_number || pkg.partition_sha256 !== board.partition_sha256)) {
    throw new Error("Firmware package does not match the existing identity and partition layout.");
  }
  const segments = pkg.segments?.slice().sort((a, b) => a.address - b.address) ?? [];
  const allowed = mode === "blank" ? [0, PARTITION_ADDRESS, APP_ADDRESS] : [APP_ADDRESS];
  if (mode === "blank" && segments.some(({ address }) => address === OTA_ADDRESS)) allowed.splice(2, 0, OTA_ADDRESS);
  if (mode === "blank" && modelKey === "lily_v2") allowed.push(0x610000);
  if (segments.length !== allowed.length || segments.some(({ address }, index) => address !== allowed[index])) {
    throw new Error("Firmware package contains an unexpected flash region.");
  }
  const fileArray = [];
  let layout;
  for (const [index, segment] of segments.entries()) {
    const data = decode(segment.data_base64);
    const end = segment.address + Math.ceil(data.length / SECTOR_SIZE) * SECTOR_SIZE;
    let limit = mode !== "blank" ? APP_ADDRESS + board.appSize : allowed[index + 1] ?? FLASH_SIZE;
    if (segment.address === 0 && (data[0] !== 0xe9 || data[2] !== 2 || data[12] !== 9 || data[13] !== 0)) {
      throw new Error("Factory package requires a DIO bootloader for ESP32-S3.");
    }
    if (segment.address === PARTITION_ADDRESS) {
      layout = partitions(data);
      if (data.length !== 3072 || !layout.some(({ type, subtype, address }) => type === 0 && subtype === 0x10 && address === APP_ADDRESS)) {
        throw new Error("Factory package contains an unsupported partition table.");
      }
      const padded = new Uint8Array(SECTOR_SIZE).fill(255);
      padded.set(data);
      if (await sha256(padded) !== pkg.partition_sha256) throw new Error("Factory partition table checksum does not match.");
      limit = PARTITION_ADDRESS + SECTOR_SIZE;
    }
    if (segment.address === OTA_ADDRESS) limit = OTA_ADDRESS + OTA_SIZE;
    if (layout && segment.address >= APP_ADDRESS) {
      const partition = layout.find(({ address }) => address === segment.address);
      if (!partition || (segment.address === APP_ADDRESS ? partition.type !== 0 : partition.type !== 1 || partition.subtype !== 0x82 || data.length !== partition.size)) {
        throw new Error("Factory firmware does not match its partition table.");
      }
      limit = partition.address + partition.size;
    }
    if (!data.length || end > limit || await sha256(data) !== segment.sha256) throw new Error("Firmware checksum or flash region validation failed.");
    if (segment.address === APP_ADDRESS && (data[0] !== 0xe9 || data[12] !== 9 || data[13] !== 0 || findIdentity(data) !== pkg.serial_number)) {
      throw new Error("Firmware application does not contain the expected Lily identity.");
    }
    fileArray.push({ address: segment.address, data });
  }
  return fileArray;
}

export async function factoryImageMatches(loader, files) {
  // An initialized filesystem can change on first boot. Boot verification
  // independently checks the app starts, including mounting v2 LittleFS.
  for (const { address, data } of files.filter(({ address }) => address <= APP_ADDRESS)) {
    if (await loader.flashMd5sum(address, data.length) !== md5Hex(data)) return false;
  }
  return true;
}

export async function verifyResume(loader, flashSize, files) {
  // Partial writes may be erased or exactly match the prepared image. Any other
  // data means this is a different board or layout and must not be overwritten.
  let address = 0;
  for (const { address: start, data } of files) {
    if (start > address && await loader.flashMd5sum(address, start - address) !== erasedMd5(start - address)) {
      throw new Error("The board contains data outside the prepared factory package.");
    }
    const size = Math.ceil(data.length / SECTOR_SIZE) * SECTOR_SIZE;
    const padded = new Uint8Array(size).fill(255);
    padded.set(data);
    const digest = await loader.flashMd5sum(start, size);
    if (digest !== md5Hex(padded) && digest !== erasedMd5(size)) {
      for (let offset = 0; offset < size; offset += 65536) {
        const current = await readExact(loader, start + offset, Math.min(65536, size - offset));
        if (!current.every((byte, index) => byte === 255 || byte === padded[offset + index])) {
          throw new Error("The board contains data that differs from the prepared factory package.");
        }
      }
    }
    address = start + size;
  }
  if (address < flashSize && await loader.flashMd5sum(address, flashSize - address) !== erasedMd5(flashSize - address)) {
    throw new Error("The board contains data outside the prepared factory package.");
  }
}

export async function writeFirmware(session, fileArray, progress) {
  await session.loader.writeFlash({
    fileArray,
    flashMode: "keep",
    flashFreq: "keep",
    flashSize: "keep",
    eraseAll: false,
    compress: true,
    calculateMD5Hash: md5Hex,
    reportProgress: (index, written, size) => progress(`Writing region ${index + 1} of ${fileArray.length} · ${Math.min(100, Math.round(100 * written / size))}%`),
  });
}

export async function verifyBoot(session, serial) {
  await session.transport.disconnect();
  await session.port.open({ baudRate: 115200 });
  const reader = session.port.readable.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  const readBoot = async () => {
    while (true) {
      const { value, done } = await reader.read();
      if (done) return false;
      buffer += decoder.decode(value, { stream: true });
      if (buffer.includes(`Lily identity: serial=${serial}\r`) || buffer.includes(`Lily identity: serial=${serial}\n`)) return true;
      buffer = buffer.slice(-512);
    }
  };
  const reading = readBoot();
  // Avoid an unhandled rejection if the port disconnects while resetting it.
  reading.catch(() => {});
  let timeout;
  try {
    await resetBoard(session.transport);
    const booted = await Promise.race([reading, new Promise((resolve) => { timeout = setTimeout(() => resolve(false), 35000); })]);
    if (!booted) throw new Error("Flash verified, but the expected Lily identity did not appear after reboot.");
  } finally {
    clearTimeout(timeout);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
    await session.port.close();
  }
}

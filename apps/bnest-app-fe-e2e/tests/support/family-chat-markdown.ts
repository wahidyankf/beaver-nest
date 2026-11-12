import { deflateSync } from "node:zlib";
import { type BrowserContext, type Locator, type Page } from "@playwright/test";
import { messageById } from "./family-chat-gestures";

// Support for family_chat.feature's "Formatted messages" rule: the remote images a
// scenario's message names, and which message a Then step is about.
//
// A remote image never leaves the machine: the browser context answers every request
// to the example origin with a real PNG generated here (no real internet is used).

export const REMOTE_IMAGE_ORIGIN = "https://images.example.test";

// The bodies the rule's Givens send. The unit adapter (`family_chat_markdown.steps.ts`)
// records the same strings, so a change here is a change there.
export const TWO_LINES = "First line\nSecond line";
export const WIDE_MESSAGE =
  "![Wide banner](https://images.example.test/banner.png)\n\n" +
  "| Day | Dinner | Chores | Notes | Shopping | Reminders |\n" +
  "| --- | --- | --- | --- | --- | --- |\n" +
  "| Monday | Soup and bread | Laundry | Call grandma | Milk, eggs, rice | Dentist at ten |";

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    table[index] = value >>> 0;
  }
  return table;
})();

function crc32(bytes: Buffer): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc = (CRC_TABLE[(crc ^ byte) & 0xff] ?? 0) ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typed = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(typed));
  return Buffer.concat([length, typed, checksum]);
}

/** A solid-colour 8-bit RGB PNG of the given size: a real file a browser decodes. */
export function makePng(width: number, height: number): Buffer {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  // Byte 8 is the bit depth (8); byte 9 is the colour type (2, RGB).
  header[8] = 8;
  header[9] = 2;
  const rowBytes = 1 + width * 3;
  const pixels = Buffer.alloc(rowBytes * height);
  for (let row = 0; row < height; row += 1) {
    const start = row * rowBytes;
    for (let column = 0; column < width; column += 1) {
      const at = start + 1 + column * 3;
      pixels[at] = 0x80;
      pixels[at + 1] = 0xc5;
      pixels[at + 2] = 0xb8;
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(pixels)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

const WIDE_PNG = makePng(1200, 60);
const SQUARE_PNG = makePng(64, 64);

/**
 * Answers every request to the remote image origin with a real PNG, for every page in the
 * context. The wide banner is wider than a phone, so the layout rule has something to hold.
 */
export async function serveRemoteImages(
  context: BrowserContext,
): Promise<void> {
  await context.route(`${REMOTE_IMAGE_ORIGIN}/**`, (route) => {
    const path = new URL(route.request().url()).pathname;
    return route.fulfill({
      status: 200,
      contentType: "image/png",
      body: path.includes("banner") ? WIDE_PNG : SQUARE_PNG,
    });
  });
}

// Which message a Then step is about. A scenario that sent another member's message or replied
// names it here; an own send leaves no entry, so the newest rendered row is the message. Keyed by
// the page, which is per scenario, so one scenario never reads another's message.
const targetIds = new WeakMap<Page, string>();

export function setTargetMessage(page: Page, messageId: string): void {
  targetIds.set(page, messageId);
}

export function targetIdOf(page: Page): string | undefined {
  return targetIds.get(page);
}

export function targetMessage(page: Page): Locator {
  const messageId = targetIds.get(page);
  return messageId
    ? messageById(page, messageId)
    : page.locator('[data-role="family-chat-message"]').last();
}

/** The message's rendered body element (the server's markdown element, or the text fallback). */
export function targetBody(page: Page): Locator {
  return targetMessage(page).locator('[data-role="family-chat-message-body"]');
}

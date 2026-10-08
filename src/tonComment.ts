/**
 * Builds the base64 BoC payload that carries a plain text comment in a TON transfer.
 * TonConnect requires the payload as a serialized cell, and the on-chain comment is what
 * the backend uses to match a deposit with the real blockchain transaction.
 */
export function encodeCommentPayload(comment: string): string {
  const text = new TextEncoder().encode(comment);
  if (text.length > 120) throw new Error('Comentário de pagamento muito longo.');

  // Cell data: 32 zero bits (text comment opcode) + utf8 bytes.
  const data = new Uint8Array(4 + text.length);
  data.set(text, 4);

  const descriptors = new Uint8Array([0x00, data.length * 2]);
  const cell = new Uint8Array([...descriptors, ...data]);
  const boc = new Uint8Array([
    0xb5, 0xee, 0x9c, 0x72, // magic
    0x01, // no index, no crc, 1 byte per cell ref
    0x01, // offset bytes
    0x01, // cells count
    0x01, // roots count
    0x00, // absent
    cell.length, // total cells size
    0x00, // root index
    ...cell,
  ]);

  let binary = '';
  boc.forEach(byte => { binary += String.fromCharCode(byte); });
  return btoa(binary);
}

import { createHmac, timingSafeEqual } from 'node:crypto';

const MAX_AUTH_AGE_SECONDS = 60 * 60 * 24;

export default function handler(request, response) {
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return response.status(405).json({ error: 'Method not allowed.' });
  }

  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) {
    return response.status(503).json({ error: 'Telegram authentication is not configured.' });
  }

  const initData = typeof request.body?.initData === 'string' ? request.body.initData : '';
  const params = new URLSearchParams(initData);
  const receivedHash = params.get('hash') || '';
  params.delete('hash');

  const dataCheckString = [...params.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');

  const secretKey = createHmac('sha256', 'WebAppData').update(botToken).digest();
  const expectedHash = createHmac('sha256', secretKey).update(dataCheckString).digest('hex');
  const received = Buffer.from(receivedHash, 'hex');
  const expected = Buffer.from(expectedHash, 'hex');
  const isValid = received.length === expected.length && timingSafeEqual(received, expected);

  const authDate = Number(params.get('auth_date'));
  const isFresh = Number.isFinite(authDate) && Math.abs(Date.now() / 1000 - authDate) <= MAX_AUTH_AGE_SECONDS;

  if (!isValid || !isFresh) {
    return response.status(401).json({ error: 'Invalid or expired Telegram initData.' });
  }

  const user = JSON.parse(params.get('user') || 'null');
  return response.status(200).json({ ok: true, user });
}

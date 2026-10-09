export const PAYMENT_CHANNEL = '@MythicSeasPayout';
export type PaymentNotice = {
  id: string; kind: 'deposit' | 'withdrawal'; amount_ton: number | string;
  amount_fc: number | string; wallet: string | null; tx_hash: string; occurred_at: string;
};
export function eligiblePayment(kind: string, status: string, hash: string | null, amount: number) {
  return Number.isFinite(amount) && amount > 0 && Boolean(hash?.trim()) &&
    (kind === 'deposit' ? status === 'credited' : kind === 'withdrawal' && ['paid', 'completed'].includes(status));
}
const escape = (value: string) => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
export function paymentCaption(notice: PaymentNotice) {
  const amount = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 9 }).format(Number(notice.amount_ton));
  const title = notice.kind === 'deposit' ? '⚓ Depósito confirmado' : '✅ Saque pago';
  const wallet = notice.wallet ? `${notice.wallet.slice(0, 6)}…${notice.wallet.slice(-4)}` : 'Não informada';
  const date = new Date(notice.occurred_at).toLocaleString('pt-BR', { timeZone: 'UTC' });
  const berries = notice.kind === 'deposit' && Number(notice.amount_fc) > 0
    ? `\n🪙 ${new Intl.NumberFormat('pt-BR').format(Number(notice.amount_fc))} BERRIES creditados` : '';
  return `<b>${title} — ${amount} TON</b>${berries}\n👛 ${escape(wallet)}\n🔗 <a href="https://tonviewer.com/transaction/${encodeURIComponent(notice.tx_hash)}">Ver na Tonviewer</a>\n🕒 ${date} UTC\n#MythicSeasbot #payout`;
}
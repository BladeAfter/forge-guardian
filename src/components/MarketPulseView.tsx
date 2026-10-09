import { useMemo, useState } from 'react';
import { ArrowDownLeft, ArrowUpRight, ChevronDown, ChevronUp } from 'lucide-react';
import { marketArt } from '../gameAssets';
import { marketPriceLabel, type MarketMine } from '../market';

type Entry = { id: string; name: string; image: string | null; amount: number; quantity: number; currency: 'FC' | 'TON'; date: string; person: string; purchase: boolean };
const exampleEntries: Entry[] = [
  { id: 'demo-1', name: 'Espadachim dos Mares', image: marketArt.hero, amount: 25000, quantity: 1, currency: 'FC', date: '2026-10-09T18:30:00Z', person: 'Capitão Azul', purchase: true },
  { id: 'demo-2', name: 'Baú de suprimentos', image: marketArt.chest, amount: 12000, quantity: 3, currency: 'FC', date: '2026-10-09T17:20:00Z', person: 'Nami do Porto', purchase: false },
  { id: 'demo-3', name: 'Parceiro de aventura', image: marketArt.pet, amount: 0.5, quantity: 1, currency: 'TON', date: '2026-10-09T16:40:00Z', person: 'Lobo do Mar', purchase: true },
  { id: 'demo-4', name: 'Baú de suprimentos', image: marketArt.chest, amount: 8000, quantity: 2, currency: 'FC', date: '2026-10-08T16:40:00Z', person: 'Barba Rubra', purchase: true },
];
const format = (n: number) => n.toLocaleString('pt-BR', { maximumFractionDigits: 3 });

export function MarketPulseView({ mine, maintenance = false }: { mine?: MarketMine; maintenance?: boolean }) {
  const [example, setExample] = useState(maintenance);
  const [currency, setCurrency] = useState<'FC' | 'TON'>('FC');
  const [expanded, setExpanded] = useState(false);
  const [selectedDay, setSelectedDay] = useState<number | null>(null);
  const entries = useMemo<Entry[]>(() => example ? exampleEntries : [
    ...(mine?.purchases ?? []).map(p => ({ id: p.id, name: p.name, image: p.image, amount: p.currency === 'TON' ? p.priceTon : p.priceFc, quantity: p.quantity ?? 1, currency: p.currency, date: p.createdAt, person: p.seller, purchase: true })),
    ...(mine?.listings ?? []).filter(l => l.status === 'sold' && l.soldAt).map(l => ({ id: l.id, name: l.name, image: l.image, amount: l.currency === 'TON' ? l.priceTon : l.priceFc, quantity: l.quantity ?? 1, currency: l.currency, date: l.soldAt ?? l.createdAt, person: '', purchase: false })),
  ].sort((a,b) => Date.parse(b.date) - Date.parse(a.date)), [mine, example]);
  const filtered = entries.filter(e => e.currency === currency);
  const ranking = Object.values(filtered.reduce<Record<string, { name: string; quantity: number; image: string | null }>>((acc, entry) => {
    const row = acc[entry.name] ?? { name: entry.name, quantity: 0, image: entry.image };
    row.quantity += entry.quantity; acc[entry.name] = row; return acc;
  }, {})).sort((a,b) => b.quantity - a.quantity).slice(0,3);
  const now = Date.now();
  const values = example ? (currency === 'FC' ? [0, 0, 0, 0, 0, 8000, 37000] : [0,0,0,0,0,0,.5]) : Array.from({length:7}, (_,i) => filtered.filter(e => {
    const days = Math.floor((now - Date.parse(e.date)) / 86400000); return days === 6-i;
  }).reduce((sum,e) => sum + e.amount,0));
  const max = Math.max(...values,1);
  const points = values.map((n,i) => `${12+i*46},${96-(n/max)*72}`).join(' ');
  const buys = entries.filter(e => e.purchase).length;
  const sales = entries.filter(e => !e.purchase).length;
  return <section className="market-pulse">
    <div className="market-port"><img src={marketArt.port} width={1280} height={768} alt="Porto de comércio de Mythic Seas" /><div><span>MYTHIC SEAS · PORTO DE COMÉRCIO</span><h2>Pulso do Mercado</h2></div></div>
    <div className="market-pulse-body">
      <div className="market-data-mode"><span>{example ? 'EXEMPLO ILUSTRATIVO · DADOS FICTÍCIOS' : 'SUAS NEGOCIAÇÕES CONFIRMADAS'}</span><label><input type="checkbox" checked={example} onChange={e => { setExample(e.target.checked); setSelectedDay(null); }} />Exemplo</label></div>
      <div className="market-overview"><div><span>Mais negociado</span><strong>{ranking[0]?.name ?? 'Sem negociações'}</strong></div><div><span>Compras / vendas</span><strong>{buys} <small>/</small> {sales}</strong></div><div><span>{example ? 'Volume de exemplo' : 'Seu volume registrado'}</span><strong>{format(filtered.reduce((sum,e) => sum+e.amount,0))} <small>{currency === 'FC' ? 'BERRIES' : 'TON'}</small></strong></div></div>
      <div className="market-section-title"><h3>Volume negociado</h3><div className="market-currency-switch">{(['FC','TON'] as const).map(c => <button key={c} type="button" aria-pressed={currency === c} onClick={() => { setCurrency(c); setSelectedDay(null); }}>{c === 'FC' ? 'BERRIES' : c}</button>)}</div></div>
      <div className="market-chart"><div><span>Últimos 7 dias</span><strong>{selectedDay !== null ? `${format(values[selectedDay])} ${currency === 'FC' ? 'BERRIES' : 'TON'}` : 'Volume diário'}</strong></div><svg viewBox="0 0 300 112" role="img" aria-label="Gráfico de volume de negociações nos últimos sete dias"><path className="market-chart-grid" d="M12 24H288 M12 60H288 M12 96H288" /><polygon className="market-chart-fill" points={`12,104 ${points} 288,104`} /><polyline className="market-chart-line" points={points} />{values.map((v,i) => <circle key={i} cx={12+i*46} cy={96-(v/max)*72} r={selectedDay === i ? 5 : 3} className="market-chart-point" />)}</svg><div className="market-chart-days">{values.map((_,i) => <button key={i} type="button" aria-label={`Volume ${i === 6 ? 'hoje' : `${6-i} dias atrás`}`} aria-pressed={selectedDay === i} onClick={() => setSelectedDay(i)}>{i === 6 ? 'Hoje' : `-${6-i}d`}</button>)}</div></div>
      <div className="market-section-title"><h3>Itens mais negociados</h3><span>{currency === 'FC' ? 'BERRIES' : 'TON'}</span></div>
      {ranking.length ? <ol className="market-ranking">{ranking.map((row,i) => <li key={row.name}><span className="market-rank-number">0{i+1}</span>{row.image && <img src={row.image} alt="" width={42} height={42} loading="lazy" />}<strong>{row.name}</strong><span>{row.quantity} un.</span></li>)}</ol> : <p className="market-pulse-empty">Nenhuma negociação registrada nesta moeda.</p>}
      <div className="market-section-title"><h3>{example ? 'Últimas vendas · exemplo' : 'Seu histórico de compras e vendas'}</h3><button type="button" className="market-expand" onClick={() => setExpanded(v => !v)} aria-expanded={expanded}>{expanded ? <ChevronUp size={18} /> : <ChevronDown size={18} />}<span>{expanded ? 'Menos' : 'Tudo'}</span></button></div>
      <ul className="market-activity">{entries.slice(0,expanded ? 50 : 3).map(e => <li key={`${e.purchase}-${e.id}`}><span className={e.purchase ? 'market-activity-buy' : 'market-activity-sell'}>{e.purchase ? <ArrowDownLeft size={16} /> : <ArrowUpRight size={16} />}</span><div><p>{example ? <><b>{e.person}</b> comprou <b>{e.name}</b></> : <>{e.purchase ? 'Você comprou' : 'Você vendeu'} <b>{e.name}</b></>}</p><span>{example ? 'Venda fictícia' : new Date(e.date).toLocaleString('pt-BR')}{!example && e.purchase && e.person ? ` · Vendedor: ${e.person}` : ''} · {e.quantity} un.</span></div><strong>{marketPriceLabel({currency:e.currency,priceFc:e.amount,priceTon:e.amount})}</strong></li>)}</ul>
      {!entries.length && <p className="market-pulse-empty">Seu histórico aparecerá após uma negociação confirmada.</p>}
    </div>
  </section>;
}
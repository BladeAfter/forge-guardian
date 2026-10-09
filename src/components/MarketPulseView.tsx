import { useId, useMemo, useState } from 'react';
import { ArrowDownLeft, ArrowUpRight, ChevronDown, ChevronUp, TrendingUp } from 'lucide-react';
import { marketArt } from '../gameAssets';
import { marketPriceLabel, type MarketMine } from '../market';
import { OceanControl } from './OceanControl';

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
  const chartId = useId().replace(/:/g, '');
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
  const chartY = (n: number) => 64 - (n / max) * 50;
  const curve = values.reduce((path, value, i) => i === 0 ? `M12 ${chartY(value)}` : `${path} C${12+(i-1)*46+23} ${chartY(values[i-1])},${12+i*46-23} ${chartY(value)},${12+i*46} ${chartY(value)}`, '');
  const buys = entries.filter(e => e.purchase).length;
  const sales = entries.filter(e => !e.purchase).length;
  return <section className="market-pulse">
    <div className="market-port market-port-mini"><img src={marketArt.port} width={96} height={64} alt="Porto de comércio de Mythic Seas" /><div><h2>Pulso do Mercado</h2><span>{ranking[0]?.name ?? 'Sem negociações'} · {buys} compras</span></div><em>{entries.length ? 'ATIVO' : 'CALMO'}</em></div>
    <div className="market-pulse-body">
      <div className="market-data-mode"><span>{example ? 'EXEMPLO ILUSTRATIVO · DADOS FICTÍCIOS' : 'SUAS NEGOCIAÇÕES CONFIRMADAS'}</span><label><input type="checkbox" checked={example} onChange={e => { setExample(e.target.checked); setSelectedDay(null); }} />Exemplo</label></div>
      <div className="market-overview market-overview-line"><strong>{ranking[0]?.name ?? 'Sem negociações'}</strong><span><b>{buys}</b> / {sales}</span><span><b>{format(filtered.reduce((sum,e) => sum+e.amount,0))}</b> {currency === 'FC' ? 'BERRIES' : 'TON'}</span></div>
      <div className="market-chart">
        <div className="market-chart-heading"><div><h3><TrendingUp size={14} />Volume negociado</h3><span>Últimos 7 dias</span></div><div className="market-currency-switch">{(['FC','TON'] as const).map(c => <OceanControl key={c} aria-pressed={currency === c} onClick={() => { setCurrency(c); setSelectedDay(null); }}>{c === 'FC' ? 'BERRIES' : c}</OceanControl>)}</div></div>
        <div className="market-chart-reading"><strong>{format(selectedDay !== null ? values[selectedDay] : values.reduce((sum,v) => sum+v,0))}<small> {currency === 'FC' ? 'BERRIES' : 'TON'}</small></strong><span>{selectedDay !== null ? selectedDay === 6 ? 'Hoje' : `${6-selectedDay} dias atrás` : 'Total no período'}</span></div>
        <svg viewBox="0 0 300 76" preserveAspectRatio="none" role="img" aria-label="Gráfico de volume de negociações nos últimos sete dias"><defs><linearGradient id={`${chartId}-fill`} x1="0" y1="0" x2="0" y2="1"><stop offset="0%" className="market-chart-gradient-top" /><stop offset="100%" className="market-chart-gradient-bottom" /></linearGradient></defs><path className="market-chart-grid" d="M12 14H288 M12 39H288 M12 64H288" />{values.map((_,i) => <path key={i} className="market-chart-grid-vertical" d={`M${12+i*46} 10V68`} />)}<path fill={`url(#${chartId}-fill)`} d={`${curve} L288 72 L12 72 Z`} />{selectedDay !== null && <path className="market-chart-cursor" d={`M${12+selectedDay*46} 8V72`} />}<path className="market-chart-glow" d={curve} vectorEffect="non-scaling-stroke" /><path className="market-chart-line" d={curve} vectorEffect="non-scaling-stroke" />{values.map((v,i) => <circle key={i} cx={12+i*46} cy={chartY(v)} r={selectedDay === i ? 3.5 : 2} className="market-chart-point" />)}</svg>
        <div className="market-chart-days">{values.map((v,i) => <OceanControl key={i} aria-label={`Volume ${i === 6 ? 'hoje' : `${6-i} dias atrás`}`} aria-pressed={selectedDay === i} title={`${format(v)} ${currency === 'FC' ? 'BERRIES' : 'TON'}`} onClick={() => setSelectedDay(i)}>{i === 6 ? 'Hoje' : `-${6-i}d`}</OceanControl>)}</div>
      </div>
      <div className="market-section-title"><h3>Itens mais negociados</h3><span>{currency === 'FC' ? 'BERRIES' : 'TON'}</span></div>
      {ranking.length ? <ol className="market-ranking">{ranking.map((row,i) => <li key={row.name}><span className="market-rank-number">0{i+1}</span>{row.image && <img src={row.image} alt="" width={30} height={30} loading="lazy" />}<strong>{row.name}</strong><span>{row.quantity} un.</span></li>)}</ol> : <p className="market-pulse-empty">Nenhuma negociação registrada nesta moeda.</p>}
      <div className="market-section-title"><h3>{example ? 'Últimas vendas · exemplo' : 'Seu histórico de compras e vendas'}</h3><button type="button" className="market-expand" onClick={() => setExpanded(v => !v)} aria-expanded={expanded}>{expanded ? <ChevronUp size={18} /> : <ChevronDown size={18} />}<span>{expanded ? 'Menos' : 'Tudo'}</span></button></div>
      <ul className="market-activity">{entries.slice(0,expanded ? 50 : 3).map(e => <li key={`${e.purchase}-${e.id}`}><span className={e.purchase ? 'market-activity-buy' : 'market-activity-sell'}>{e.purchase ? <ArrowDownLeft size={13} /> : <ArrowUpRight size={13} />}</span><div><p>{example ? <><b>{e.person}</b> comprou <b>{e.name}</b></> : <>{e.purchase ? 'Você comprou' : 'Você vendeu'} <b>{e.name}</b></>}</p><span>{example ? 'Venda fictícia' : new Date(e.date).toLocaleString('pt-BR')}{!example && e.purchase && e.person ? ` · Vendedor: ${e.person}` : ''} · {e.quantity} un.</span></div><strong>{marketPriceLabel({currency:e.currency,priceFc:e.amount,priceTon:e.amount})}</strong></li>)}</ul>
      {!entries.length && <p className="market-pulse-empty">Seu histórico aparecerá após uma negociação confirmada.</p>}
    </div>
  </section>;
}
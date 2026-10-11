import { useState } from 'react';
import { Check, LockKeyhole, RotateCcw } from 'lucide-react';
import { useLocalizedText } from '../LanguageContext';
import type { ShipCosmetics } from '../naval';
import { canCustomizeShip, shipCosmetics, SHIP_COLORS, COLOR_LABELS } from '../shipCustomization';
import { OceanControl } from './OceanControl';
import { ShipAppearancePreview } from './ShipAppearancePreview';

export function ShipCustomizationPanel({ classId, owned, busy, onSave }: {
  classId: string; owned?: { canCustomize?: boolean; cosmetics?: Partial<ShipCosmetics> }; busy: boolean;
  onSave: (cosmetics: ShipCosmetics) => Promise<boolean>;
}) {
  const text = useLocalizedText();
  const [draft, setDraft] = useState(() => shipCosmetics(owned?.cosmetics));
  const [saving, setSaving] = useState(false);
  if (!canCustomizeShip(owned)) return <div className="ship-fleet__style-locked"><LockKeyhole size={24} /><p>{text('Personalização disponível apenas nos navios comprados.')}</p></div>;
  const change = (key: keyof ShipCosmetics, value: string) => setDraft(d => ({ ...d, [key]: value }));
  const dirty = JSON.stringify(draft) !== JSON.stringify(shipCosmetics(owned?.cosmetics));
  const disabled = busy || saving;
  return <div className="ship-fleet__customization">
    <ShipAppearancePreview classId={classId} cosmetics={draft} />
    {([['hullColor', 'Cor do casco'], ['sailColor', 'Cor das velas'], ['flagColor', 'Cor da bandeira']] as const).map(([key, label]) => <fieldset key={key} disabled={disabled}>
      <legend>{text(label)}</legend><div className="ship-fleet__swatches" role="group" aria-label={text(label)}>
        {SHIP_COLORS.filter(c => key !== 'flagColor' || c !== 'original').map(c => <OceanControl key={c} className={`ship-fleet__swatch ship-fleet__swatch--${c}`} aria-label={`${text(label)} · ${text(COLOR_LABELS[c])}`} title={text(COLOR_LABELS[c])} aria-pressed={draft[key] === c} onClick={() => change(key, c)}>{draft[key] === c ? <Check size={18} /> : c === 'original' ? <RotateCcw size={16} /> : null}</OceanControl>)}
      </div>
    </fieldset>)}
    <div className="ship-fleet__style-selects">
      {([
        ['flag', 'Emblema da bandeira', [['skull','Caveira'],['sun','Sol'],['moon','Lua']]],
        ['prow', 'Figura de proa', [['none','Sem figura'],['lion','Leão'],['blade','Lâmina']]],
        ['decoration', 'Decoração', [['none','Sem decoração'],['gold','Ouro'],['silver','Prata']]],
        ['trail', 'Esteira e efeitos', [['foam','Espuma'],['embers','Brasas'],['mist','Névoa']]],
      ] as const).map(([key, label, options]) => <label key={key}>{text(label)}<select disabled={disabled} aria-label={text(label)} value={draft[key]} onChange={e => change(key, e.target.value)}>{options.map(([value, name]) => <option key={value} value={value}>{text(name)}</option>)}</select></label>)}
    </div>
    <div className="ship-fleet__actions">
      <OceanControl className="ship-fleet__ghost" disabled={disabled || !dirty} onClick={() => setDraft(shipCosmetics(owned?.cosmetics))}><RotateCcw size={16} />{text('RESTAURAR')}</OceanControl>
      <OceanControl className="ship-fleet__primary" disabled={disabled || !dirty} onClick={async () => { setSaving(true); try { await onSave(draft); } finally { setSaving(false); } }}><Check size={16} />{text('SALVAR APARÊNCIA')}</OceanControl>
    </div>
  </div>;
}
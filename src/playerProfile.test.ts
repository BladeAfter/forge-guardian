import {describe,expect,it} from 'vitest';
import {getDisplayName,getInitials,type TelegramPlayerProfile} from './playerProfile';

const profile=(values:Partial<TelegramPlayerProfile>={}):TelegramPlayerProfile=>({telegramId:'8118569391',firstName:'Allan',lastName:'Marques',username:'BladeAfter',photoUrl:null,...values});

describe('Telegram player profile',()=>{
  it('mantém o Telegram ID como string',()=>expect(profile().telegramId).toBe('8118569391'));
  it('combina nome e sobrenome reais',()=>expect(getDisplayName(profile())).toBe('Allan Marques'));
  it('usa username quando o nome está vazio',()=>expect(getDisplayName(profile({firstName:'',lastName:null}))).toBe('BladeAfter'));
  it('usa Jogador como último fallback',()=>expect(getDisplayName(profile({firstName:'',lastName:null,username:null}))).toBe('Jogador'));
  it('gera iniciais sem avatar fixo',()=>expect(getInitials('Allan Marques')).toBe('AM'));
});

export type TelegramPlayerProfile={telegramId:string;firstName:string;lastName:string|null;username:string|null;photoUrl:string|null};

export function getDisplayName(profile:TelegramPlayerProfile):string{
  return [profile.firstName,profile.lastName].filter(Boolean).join(' ').trim()||profile.username||'Jogador';
}

export function getInitials(name:string):string{
  return name.split(/\s+/).filter(Boolean).slice(0,2).map(part=>part[0]).join('').toUpperCase()||'J';
}

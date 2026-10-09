import { usePlayerHeroes } from '../hooks';
import { useLanguage } from '../LanguageContext';
import { CrewDeck } from '../components/CrewDeck';

export function HeroesPage({ telegramInitData, onClose }: { telegramInitData: string; onClose: () => void }) {
  const { data, isLoading, isFetching, error, refetch } = usePlayerHeroes(telegramInitData, true);
  const { tError } = useLanguage();
  const telegramId = (() => {
    try {
      const user = JSON.parse(new URLSearchParams(telegramInitData).get('user') ?? 'null');
      return user?.id ? String(user.id) : undefined;
    } catch { return undefined; }
  })();
  return <CrewDeck heroes={data?.heroes ?? []} telegramInitData={telegramInitData} telegramId={telegramId}
    onClose={onClose} loading={isLoading && isFetching}
    error={error ? tError(error) || 'Não foi possível reunir a tripulação.' : isLoading && !isFetching ? 'A tripulação está indisponível no momento.' : undefined}
    onRetry={() => void refetch()} />;
}

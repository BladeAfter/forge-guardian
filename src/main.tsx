import React from 'react';
import ReactDOM from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'sonner';
import App from './App';
import './styles.css';
import { TonConnectUIProvider } from '@tonconnect/ui-react';
import { TONCONNECT_MANIFEST_URL } from './config';
import { LanguageProvider } from './LanguageContext';

/**
 * `networkMode: 'always'` is mandatory inside Telegram webviews: Android/iOS
 * frequently report `navigator.onLine === false` even with a working connection.
 * With the default 'online' mode React Query PAUSES the fetch, leaving the query
 * in `pending` forever — that is what kept PvP/Heroes/Season Pass/Events stuck on
 * "Loading...". Paused queries never fail, never resolve and never show an error.
 */
const queryClient = new QueryClient({
  defaultOptions: {
    queries: { networkMode: 'always', retry: 1, retryDelay: 800 },
    mutations: { networkMode: 'always' },
  },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <LanguageProvider>
        <TonConnectUIProvider manifestUrl={TONCONNECT_MANIFEST_URL}>
          <App />
        </TonConnectUIProvider>
      </LanguageProvider>
      <Toaster position="top-right" />
    </QueryClientProvider>
  </React.StrictMode>
);

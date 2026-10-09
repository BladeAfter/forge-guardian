import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    proxy: {
      // Local Vite has no Lovable asset gateway; deployed apps use their own origin.
      '/__l5e/assets-v1/': {
        target: 'https://id-preview--a1010e38-3156-4844-b5b9-f707f0d57268.lovable.app',
        changeOrigin: true
      }
    }
  }
});

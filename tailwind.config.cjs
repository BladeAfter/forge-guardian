module.exports = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        forge: {
          black: '#07090d',
          surface: '#10131a',
          navy: '#0f172a',
          gold: '#d5b455',
          ember: '#e26c35'
        }
      },
      boxShadow: {
        card: '0 20px 80px rgba(0,0,0,0.35)'
      },
      backgroundImage: {
        'gradient-radial': 'radial-gradient(circle at center, var(--tw-gradient-stops))'
      }
    }
  },
  plugins: []
};

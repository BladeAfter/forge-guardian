module.exports = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        forge: {
          black: 'hsl(var(--forge-black) / <alpha-value>)',
          surface: 'hsl(var(--forge-surface) / <alpha-value>)',
          navy: 'hsl(var(--forge-navy) / <alpha-value>)',
          gold: 'hsl(var(--forge-gold) / <alpha-value>)',
          ember: 'hsl(var(--forge-ember) / <alpha-value>)'
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

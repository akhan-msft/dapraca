import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'build',   // Match Node.js BFF expectation: client/build
  },
  server: {
    proxy: {
      '/api': 'http://localhost:3000',   // Dev: proxy API calls to Node BFF
    },
  },
})

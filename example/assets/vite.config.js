import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

// Built into ../priv/static/app and served by Phoenix at /app/. `npm run dev`
// runs Vite on :5173 and forwards /api and the /socket WebSocket to Phoenix
// on :4000 (mix phx.server).
export default defineConfig({
  base: "/app/",
  plugins: [vue()],
  build: { outDir: "../priv/static/app", emptyOutDir: true },
  server: {
    proxy: {
      "/api": "http://localhost:4000",
      "/socket": { target: "ws://localhost:4000", ws: true },
    },
  },
});

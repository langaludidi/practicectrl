import type { Config } from "tailwindcss";

export default {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        pc: {
          navy: "#051A39",
          "navy-soft": "#0D2A4B",
          teal: "#029EA1",
          "teal-action": "#067C80",
          blue: "#236CFB",
          canvas: "#F6F8FA",
          ink: "#12243B",
          muted: "#5B6B7D",
          line: "#DCE3EA",
        },
      },
    },
  },
  plugins: [],
} satisfies Config;

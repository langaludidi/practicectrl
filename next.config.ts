import type { NextConfig } from "next";

// A Git preview must never load the connected live tenant's backend. This
// check runs during the build, before Vercel can create a usable deployment.
if (process.env.VERCEL === "1" && process.env.VERCEL_ENV !== "production") {
  const previewBackend = "https://hyajnfdzarbygkvvfbnd.supabase.co";
  if (process.env.NEXT_PUBLIC_SUPABASE_URL !== previewBackend) {
    throw new Error("Preview deployment requires the isolated PracticeCtrl Development Supabase URL");
  }
}

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
          { key: "X-Robots-Tag", value: "noindex, nofollow, noarchive" }
        ]
      }
    ];
  }
};
export default nextConfig;

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function createClient() {
  const store = await cookies();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error("Supabase server configuration is missing");

  return createServerClient(url, key, {
    cookies: {
      getAll() { return store.getAll(); },
      setAll(items: Array<{ name: string; value: string; options?: any }>) {
        try { items.forEach(({ name, value, options }) => store.set(name, value, options)); }
        catch { /* Server Component: middleware refreshes the session cookie. */ }
      }
    }
  });
}

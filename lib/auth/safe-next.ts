/** Resolve a post-authentication destination on this application's origin only. */
export function safeNext(value: string | null, requestUrl: URL): URL {
  const fallback = new URL("/dashboard", requestUrl);
  if (!value || !value.startsWith("/") || value.startsWith("//")) return fallback;
  try {
    const destination = new URL(value, requestUrl);
    return destination.origin === requestUrl.origin ? destination : fallback;
  } catch {
    return fallback;
  }
}

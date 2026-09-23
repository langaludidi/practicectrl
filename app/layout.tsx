import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PracticeCtrl",
  description: "Clinical Operations. Coding Intelligence. Revenue Integrity.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}

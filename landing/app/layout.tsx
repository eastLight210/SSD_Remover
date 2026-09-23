import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://ssdremover.badgerworks.dev"),
  title: "SSD Remover — Find the blocker. Eject safely.",
  description: "See what is blocking your external drive, close only what you choose, and eject it safely on macOS.",
  applicationName: "SSD Remover",
  keywords: ["macOS", "external drive", "SSD", "safe eject", "menu bar app"],
  alternates: { canonical: "/" },
  openGraph: {
    title: "SSD Remover — Find the blocker. Eject safely.",
    description: "Turn “disk in use” into a short, reviewable, local workflow.",
    type: "website",
    images: [{ url: "/og.png", width: 1200, height: 630, alt: "SSD Remover for macOS" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "SSD Remover — Find the blocker. Eject safely.",
    description: "Turn “disk in use” into a short, reviewable, local workflow.",
    images: ["/og.png"],
  },
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
};

export const viewport: Viewport = {
  colorScheme: "dark",
  themeColor: "#060608",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={inter.variable}>{children}</body>
    </html>
  );
}

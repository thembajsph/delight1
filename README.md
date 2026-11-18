# Delight — Africa's Super App

Flutter • XRP Ledger • Ozow EFT • PayShap • VALR • Supabase

## Quick Start

```bash
flutter pub get
flutter run          # testnet + offline mode by default
```

Full setup instructions with all links: see SETUP_GUIDE.txt
Backend API: see backend/ folder (Node.js + TypeScript)

## Architecture

```
Flutter App  →  Your Backend (Railway)  →  VALR (ZAR/XRP swap)
                     │                  →  XRPL (send XRP)
                     │                  →  Ozow (EFT webhook)
                     │                  →  Firebase (push)
                     └──────────────────→  Supabase (DB/Auth)
```

## Fonts (free)
- Clash Display: https://www.fontshare.com/fonts/clash-display
- Satoshi: https://www.fontshare.com/fonts/satoshi
Place .otf files in assets/fonts/

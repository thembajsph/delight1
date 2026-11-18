# Delight — Backend Deploy Guide

## One-time setup (your terminal only — secrets never in chat)

### 1. Install Supabase CLI
```bash
npm install -g supabase
supabase login
supabase link --project-ref pclhfcmxpzpqaigyyhjz
```

### 2. Run the database schema
Go to: https://supabase.com/dashboard/project/pclhfcmxpzpqaigyyhjz/sql/new
Paste the contents of: `supabase/migrations/20240101_delight_schema.sql`
Click Run.

### 3. Set your secrets (type in YOUR terminal — never share these)
```bash
# VALR Exchange (get from valr.com → API Keys)
supabase secrets set VALR_API_KEY=your_valr_api_key_here
supabase secrets set VALR_API_SECRET=your_valr_secret_here

# Your XRP hot wallet (the address that mints NFT tickets)
supabase secrets set HOT_WALLET_ADDRESS=rYourMainnetXRPAddress
supabase secrets set HOT_WALLET_SEED=sYourWalletSeedHere

# EFT payout provider (Peach Payments — peachpayments.com/za/developers)
supabase secrets set EFT_API_KEY=your_peach_api_key
supabase secrets set EFT_API_SECRET=your_peach_secret
supabase secrets set EFT_API_URL=https://api.peachpayments.com/v1/payouts

# NFT metadata storage (nft.storage — free, permanent)
supabase secrets set NFT_STORAGE_KEY=your_nft_storage_key

# Testnet mode (set to "false" when going live)
supabase secrets set XRPL_TESTNET=true
```

### 4. Deploy edge functions
```bash
supabase functions deploy cashout
supabase functions deploy send_payment
supabase functions deploy balance_sync
supabase functions deploy mint_ticket
```

### 5. Test cashout locally first
```bash
supabase functions serve cashout --env-file .env.local
curl -X POST http://localhost:54321/functions/v1/cashout \
  -H "Authorization: Bearer YOUR_USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{"zarAmount":50,"accountName":"Themba Sithole","accountNumber":"12345678","bankName":"FNB"}'
```

## EFT Provider options (all free for the sender)

| Provider | Setup | Time | Notes |
|----------|-------|------|-------|
| **Peach Payments** | 2–3 days | 1–2 days | Best SA support, easy API |
| **Netcash** | 3–5 days | 1–2 days | Established, reliable |
| **Direct Bank** | Weeks | Same day | Only worth it at R500k+/month |

## When Flash API is ready (airtime top-up)
Add a new edge function: `supabase/functions/airtime_topup/index.ts`
It calls Flash API → sends airtime to phone number → deducts DC from wallet.
No EFT needed — Flash handles airtime directly.

---

## Migration 20240105 — social, rewards, insights, security hardening

Run after 20240104. Tested end-to-end against Postgres 16 (follows, reward
claims, leaderboard, vendor payments, insights, RLS).

**Things you must do by hand after applying it**

1. **Make yourself admin (SQL editor).** The app can no longer promote a user to
   `role='admin'` (that was a self-service hole). Run once:
   `update public.profiles set role = 'admin' where email = 'you@yourdomain.com';`
   The admin dashboard and `get_event_insights` check this DB role.
2. **Review reward amounts.** Every claimed reward credits `wallets.balance_dc`
   — a real liability at cash-out. Edit `reward_tasks.reward_dc`, or set
   `active = false` to pause rewards.
3. **Register vendors** for an event in `event_vendors` (name, category, emoji,
   `owner_id` = the vendor's user id). Insights fill in only from payments made
   through the `pay_event_vendor` RPC (`SupabaseService.payEventVendor`).
   There is no in-app vendor-pay screen yet.
4. Optionally set `events.venue_type` (`club|stadium|concert|church|arena|restaurant`)
   so Indoor Insights labels the venue.

---

## Migration 20240106 — products, AI, messaging, private events, security round 2

Run after 20240105 (safe to re-run). Tested on Postgres 16: RLS, grants, guards,
messaging, itemised payments, product insights, recommendations, private
events/RSVP, comments, exclusive posts, atomic wallet ops, top-up reference.

**Do these by hand**

1. **Secrets** (`supabase secrets set NAME=value`):
   `ANTHROPIC_API_KEY`, optional `AI_MODEL` (default `claude-sonnet-5-5`),
   `WEBHOOK_SECRET` (top-up webhook HMAC; the webhook refuses everything
   without it), `BANK_NAME`, `BANK_ACCOUNT_NAME`, `BANK_ACCOUNT_NUMBER`,
   `BANK_BRANCH_CODE`, and for the XRPL hot wallet `HOT_WALLET_SEED` /
   `HOT_WALLET_ADDRESS` (see MAINNET.md).
2. **Deploy functions:** `supabase functions deploy ai_insights topup cashout`
   (and the others you changed). Wallet credits/debits now go through
   `credit_wallet` / `debit_wallet` (service role only) — redeploy `cashout`.
3. **Realtime:** Database → Replication → make sure `messages` is in the
   `supabase_realtime` publication (the migration adds it when it exists).
4. **Storage:** bucket `delight-images` must exist. Policies are not created by
   SQL here — allow authenticated users to upload under their own folder and
   public read. Review this manually.
5. **Admin:** `update public.profiles set role='admin' where email='you@…';`
6. **Reward amounts:** review `reward_tasks.reward_dc` (liability at cash-out).
7. **Products only fill when customers pay by choosing items.** Businesses add
   products in Profile → My Products. Payments made via `pay_business_items` /
   `pay_event_vendor(p_items => …)` are itemised; prices are read from
   `business_products` server-side. The buyer-side cart UI is not built yet —
   until it is, no sales are itemised and the Products screens show an empty
   state. (Service methods: `getBusinessMenu`, `payBusinessItems`,
   `payEventVendorItems`.)

**Privacy (POPIA)** — update your privacy policy before launch: product sales
are aggregated per business; benchmarks need ≥5 other businesses; platform
trends need ≥3 businesses per group; only aggregates (never names or phone
numbers) are sent to the AI provider. Get legal review.

### Gate staff PINs (added to 20240106)
PINs are now bcrypt-hashed and checked server-side (`gate_pin_login`, 5 wrong
tries = 5-minute lock). Existing plain PINs are converted automatically and the
plain column is wiped. Organisers create/reset/remove staff in the Gate
Dashboard (Add Staff / Reset PIN); the scanner must be signed in to the
organiser's (or an admin's) account, and staff then enter their PIN.

## 0107 — profile backfill, 0108 — ticket money (run both, in order)
- `20240107_profile_backfill.sql`: gives every login a profile + wallet row (fixes "organizer_id not present in profiles" when creating events).
- `20240108_ticket_money.sql`: **required before launch.** Without it `mint_ticket` (old version) gave tickets away free.
  After running it, redeploy the function: `supabase functions deploy mint_ticket`.
  - Price comes from the event's tier in the database (`priceXRP` DC), not from the app.
  - Buyer is debited; organiser is credited price minus the 3% platform fee; tier `soldTickets` goes up; sold-out is enforced.
  - `buy_resale_ticket` now only lets the signed-in user buy for themselves, and uses DC units (ZAR / xrp_price).

## 0109 — Memory NFT guard
Run `20240109_memory_nft_guard.sql`. A Memory NFT post must reference a ticket the poster owns, for an event that
has happened or where they were scanned in. The app shows all your tickets in the New Post picker and locks the
ones whose event hasn't happened yet.

## 0110 — private-event guest invites
Run `20240110_private_event_guests.sql`. Adds: invite people already on Delight (in-app message with the RSVP link),
address-book matching, and the guest `user_id` link. The app now also needs `flutter pub get` (new package
`flutter_contacts`) and the READ_CONTACTS permission (already in AndroidManifest.xml).
Hosts can delete an event (⋮ menu in the event, or long-press the card) and remove a guest (long-press the guest).

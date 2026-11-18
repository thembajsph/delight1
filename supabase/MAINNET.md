# Moving Delight from XRPL testnet to mainnet

Model: **custodial.** Users hold a ZAR-denominated ledger balance
(`wallets.balance_dc`); Delight holds the real XRP/ZAR in accounts you control.
Users never see keys.

## 1. Legal / compliance first (do not skip)
- Holding customer funds and converting to crypto can need FSCA/FIC
  registration (FAIS/CASP, FICA/KYC). Get a South African fintech lawyer.
- Add KYC before cash-out above a threshold; keep transaction records.
- Update privacy policy + terms (POPIA).

## 2. Accounts
1. **Business bank account** — receives EFT top-ups; reference = the user's
   `topup_ref` (shown in-app). Set `BANK_*` secrets.
2. **VALR business account** — complete KYC, enable 2FA, create an API key with
   only: view, trade, withdraw (to a whitelisted address). IP-restrict it.
   Store as `VALR_API_KEY` / `VALR_API_SECRET` secrets.

## 3. Hot wallet (XRPL mainnet)
1. Generate the keypair **offline** (xrpl.js on an air-gapped machine, or a
   hardware wallet such as Ledger for the cold wallet). Never generate it on a
   server you don't control and never paste the seed in chat/email.
2. Fund with the base reserve (currently ~1 XRP) + a small float.
3. Keep **only a small float** in the hot wallet; sweep the rest to a cold
   wallet (hardware). Refill from VALR as needed.
4. Set secrets: `HOT_WALLET_SEED`, `HOT_WALLET_ADDRESS`, and `XRPL_TESTNET=false`
   (the functions read this flag). Also point `xrpl_service.dart` at
   `wss://xrplcluster.com` (or `wss://s1.ripple.com`) instead of the testnet.
5. Whitelist the hot wallet address on VALR for withdrawals/deposits.

## 4. Backend switches
- `supabase secrets set` all of the above; redeploy every function.
- Top-up webhook: point your bank/gateway to
  `https://<project>.functions.supabase.co/topup`, sign with `WEBHOOK_SECRET`
  (HMAC SHA-256, header as implemented in `topup/index.ts`). Test with a tiny
  real payment; duplicates are ignored by design.
- Cash-out: start with low limits and manual review of the first payouts.
- Rotate any key that ever touched testnet code or a chat.

## 5. Test sequence on mainnet (small amounts)
1. R50 EFT top-up → balance credited exactly once (resend webhook: no change).
2. Send between two users; check both ledgers.
3. Cash-out R50 → VALR → bank; verify refund path by forcing a failure.
4. Reconcile: bank + VALR + hot wallet ≥ sum of all `wallets.balance_dc`
   (convert at your rate). Make this a daily check.

## 6. Operations
- Daily reconciliation, alerts on failed cashouts, backups (Supabase PITR on).
- Rate-limit and monitor `credit_wallet` callers (service role only).
- Incident plan: pause cash-outs by disabling the function.

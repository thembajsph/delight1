// lib/core/config/env.dart
// ─────────────────────────────────────────────────────────────────────────────
// ALL environment variables and API keys for Delight
//
// HOW TO USE:
//   1. Copy this file to env.dart (already done)
//   2. Fill in your real keys below
//   3. Never commit real keys to Git — add env.dart to .gitignore
//      OR use --dart-define at build time (see README)
//
// BUILD WITH REAL KEYS:
//   flutter run \
//     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=eyJ... \
//     --dart-define=VALR_API_KEY=xxx \
//     --dart-define=OZOW_SITE_CODE=xxx
// ─────────────────────────────────────────────────────────────────────────────

class Env {
  // ── Supabase (DB, Auth, Storage, Realtime) ───────────────────────────────
  // Sign up free: https://supabase.com
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://pclhfcmxpzpqaigyyhjz.supabase.co');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBjbGhmY214cHpwcWFpZ3l5aGp6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxNjczMTgsImV4cCI6MjA5MDc0MzMxOH0.UKy3Lry9kNJKUtCs2T-oDgh-RoHrb_DUVa6eygsMh9I');

  // ── DC Ledger ───────────────────────────────────────────────────────────
  // Testnet (free test DC): https://faucet.altnet.rippletest.net
  // Mainnet: switch useTestnet to false
  static const useTestnet =
      bool.fromEnvironment('XRPL_TESTNET', defaultValue: true);
  static const xrplMainnet = 'wss://xrplcluster.com';
  static const xrplTestnet = 'wss://s.altnet.rippletest.net:51233';
  static String get xrplEndpoint => useTestnet ? xrplTestnet : xrplMainnet;

  static const xrplRpcMainnet = 'https://xrplcluster.com';
  static const xrplRpcTestnet = 'https://s.altnet.rippletest.net:51234';
  static String get xrplRpcEndpoint => useTestnet ? xrplRpcTestnet : xrplRpcMainnet;

  // ── Google Sign-In ──────────────────────────────────────────────────────────
  // Get from Google Cloud Console → Credentials → Web Client ID
  // Same value you pasted into Supabase Auth → Google provider
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '239829889345-c8eob4kk38aj35tpo19sgnb313hb4g43.apps.googleusercontent.com');

  // ── Reloadly (Airtime top-up — MTN, Vodacom, Cell C, Telkom, Airtel) ────────
  // Free sandbox: https://reloadly.com/signup
  // Sandbox base: https://topups-sandbox.reloadly.com
  // Production:   https://topups.reloadly.com
  // Get credentials from: https://developers.reloadly.com
  static const reloadlyClientId = String.fromEnvironment(
    'RELOADLY_CLIENT_ID', defaultValue: 'YOUR_RELOADLY_CLIENT_ID');
  static const reloadlyClientSecret = String.fromEnvironment(
    'RELOADLY_CLIENT_SECRET', defaultValue: 'YOUR_RELOADLY_SECRET');
  static const reloadlySandbox = bool.fromEnvironment(
    'RELOADLY_SANDBOX', defaultValue: true); // true = test mode, no real airtime sent

  // SA Operator IDs on Reloadly (sandbox and production same IDs)
  static const reloadlyMTN     = 341;
  static const reloadlyVodacom = 344;
  static const reloadlyCellC   = 342;
  static const reloadlyTelkom  = 2646;
  static const reloadlyAirtel  = 340;

  // ── VALR Exchange (ZAR ↔ DC) ────────────────────────────────────────────
  // Sign up: https://valr.com — get API key from dashboard
  // Permissions needed: View, Trade (NOT Withdraw)
  static const valrApiKey =
      String.fromEnvironment('VALR_API_KEY', defaultValue: 'YOUR_VALR_API_KEY');
  static const valrApiSecret =
      String.fromEnvironment('VALR_API_SECRET', defaultValue: 'YOUR_VALR_API_SECRET');
  static const valrBaseUrl = 'https://api.valr.com';

  // ── Ozow (SA Instant EFT payments) ──────────────────────────────────────
  // Sign up: https://ozow.com/developers
  // Approval takes ~3 business days
  static const ozowSiteCode =
      String.fromEnvironment('OZOW_SITE_CODE', defaultValue: 'YOUR_OZOW_SITE_CODE');
  static const ozowPrivateKey =
      String.fromEnvironment('OZOW_PRIVATE_KEY', defaultValue: 'YOUR_OZOW_PRIVATE_KEY');
  static const ozowApiKey =
      String.fromEnvironment('OZOW_API_KEY', defaultValue: 'YOUR_OZOW_API_KEY');
  static const ozowPaymentUrl = 'https://pay.ozow.com/';
  static const ozowApiUrl = 'https://api.ozow.com';

  // ── MoonPay (Easy ZAR → DC, handles KYC for you) ───────────────────────
  // Sign up: https://dashboard.moonpay.com
  // Use this for MVP — switch to Ozow+VALR for lower fees at scale
  static const moonPayPublishableKey =
      String.fromEnvironment('MOONPAY_KEY', defaultValue: 'pk_test_YOUR_MOONPAY_KEY');
  static const moonPayBaseUrl = 'https://buy.moonpay.com';
  // Use pk_live_ prefix for production

  // ── Stitch Money (PayShap / instant EFT alternative) ────────────────────
  // Sign up: https://stitch.money (enterprise, apply for access)
  static const stitchClientId =
      String.fromEnvironment('STITCH_CLIENT_ID', defaultValue: 'YOUR_STITCH_CLIENT_ID');
  static const stitchClientSecret =
      String.fromEnvironment('STITCH_CLIENT_SECRET', defaultValue: 'YOUR_STITCH_SECRET');

  // ── Your Backend API ─────────────────────────────────────────────────────
  // Deploy on Railway: https://railway.app ($5/month)
  static const apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.delight.africa');

  // ── Firebase (Push Notifications) ───────────────────────────────────────
  // Set up at: https://console.firebase.google.com
  // Add google-services.json (Android) and GoogleService-Info.plist (iOS)
  // No key needed here — Firebase SDK reads from those files automatically

  // ── Smile Identity (KYC — SA ID verification) ───────────────────────────
  // Sign up: https://usesmileid.com
  // Required for users handling > R5,000 (FICA compliance)
  static const smileApiKey =
      String.fromEnvironment('SMILE_API_KEY', defaultValue: 'YOUR_SMILE_API_KEY');
  static const smilePartnerId =
      String.fromEnvironment('SMILE_PARTNER_ID', defaultValue: 'YOUR_PARTNER_ID');

  // ── App Config ───────────────────────────────────────────────────────────
  static const appName = 'Delight';
  static const appVersion = '1.0.0';
  // Host used in shared RSVP / pay links. Must match the host in AndroidManifest.xml.
  // Override with --dart-define=LINK_HOST=your-host if you do not use delight.africa.
  static const linkHost = String.fromEnvironment('LINK_HOST', defaultValue: 'delight.africa');
  static const supportEmail = 'support@delight.africa';

  // Platform fees (must match your backend)
  static const feeP2P = 0.015;                 // 1.5%
  static const feeConsumerBusiness = 0.02;     // 2.0%
  static const feeBusinessBusiness = 0.02;     // 2.0%
  static const feeTicketSale = 0.03;           // 3.0%

  // XRPL minimum reserve (accounts need 10 DC to activate)
  static const xrplMinReserve = 10.0;
}

// supabase/functions/topup/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Top Up: ZAR → DC via EFT
//
// Option 1 (NOW): Standard EFT — user does a bank transfer to Delight's account,
//   Peach Payments / Ozow notifies us via webhook, we buy XRP on VALR and credit user.
//
// Option 2 (LATER): Flash API — airtime instead of cash.
//   User selects network, we call Flash → airtime sent to their number.
//
// Option 3 (LATER): USSD — for feature phones with no data.
//   User dials *120*DELIGHT# → follows menu → confirms top-up via USSD.
//   Requires a USSD gateway (Africa's Talking or Vodacom direct).
//
// ─────────────────────────────────────────────────────────────────────────────
// HOW EFT TOP-UP WORKS (Option 1):
//
//   1. User opens app → taps Add Money → chooses EFT
//   2. App shows Delight's bank account details + a unique reference (their user ID)
//   3. User opens their banking app and does a normal EFT transfer
//   4. Their bank sends the money → arrives in Delight's FNB/ABSA account
//   5. Peach Payments / Ozow detects the incoming payment and fires a webhook
//   6. THIS FUNCTION runs → verifies the payment → buys XRP on VALR → credits user
//   7. User gets a push notification: "R200 added to your Delight wallet"
//
// ─────────────────────────────────────────────────────────────────────────────
// SECRETS NEEDED:
//   VALR_API_KEY          — from valr.com → API Keys (Trade permission)
//   VALR_API_SECRET       — from valr.com → API Keys
//   VALR_XRP_ADDRESS      — your VALR withdrawal address (where bought XRP lands)
//   HOT_WALLET_ADDRESS    — your mainnet XRP address
//   HOT_WALLET_SEED       — your mainnet XRP seed
//   BANK_NAME / BANK_ACCOUNT_NAME / BANK_ACCOUNT_NUMBER / BANK_BRANCH_CODE / BANK_ACCOUNT_TYPE
//                         — the business account users pay into (shown in-app)
//   WEBHOOK_SECRET        — random string you set in Peach/Ozow dashboard
//                           to verify webhooks are real (not spoofed)
//   XRPL_TESTNET          — "true" for testnet, "false" for mainnet
// ─────────────────────────────────────────────────────────────────────────────

import { serve }       from "https://deno.land/std@0.208.0/http/server.ts";
import { createHmac }  from "npm:crypto";
import { adminClient, logTransaction, creditBalance, requireAuth } from "../_shared/supabase.ts";
import { buyXrp, getXrpPrice }                        from "../_shared/valr.ts";

// ── Constants ─────────────────────────────────────────────────────────────────
const APP_FEE_PERCENT = 0.005;   // 0.5% Delight fee on top-ups
const VALR_FEE_PERCENT = 0.001;  // VALR 0.1% taker fee
const MIN_TOPUP_ZAR   = 10.0;   // minimum R10 top-up

// ── Webhook signature verification ───────────────────────────────────────────
// Peach Payments signs every webhook with HMAC-SHA256
// We verify this to ensure the webhook is genuinely from them, not a hacker
function verifyPeachWebhook(payload: string, signature: string, secret: string): boolean {
  const expected = createHmac("sha256", secret).update(payload).digest("hex");
  if (expected.length !== signature.length) return false;
  let diff = 0;                                   // constant-time compare
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

// ── Credit user's Delight wallet after confirmed payment ──────────────────────
async function processConfirmedTopup(params: {
  userId:     string;
  zarAmount:  number;
  reference:  string;   // bank EFT reference
  provider:   string;   // "peach" | "ozow" | "manual"
}): Promise<{ dcCredited: number; zarSpent: number }> {
  const supabase = adminClient();

  // Calculate how much DC the user gets
  const xrpPrice     = await getXrpPrice();
  const appFeeZAR    = params.zarAmount * APP_FEE_PERCENT;
  const valrFeeZAR   = params.zarAmount * VALR_FEE_PERCENT;
  const zarToBuyWith = params.zarAmount - appFeeZAR - valrFeeZAR;
  const dcToCredit   = zarToBuyWith / xrpPrice;

  // Buy XRP on VALR with the user's ZAR (minus fees)
  const valrApiKey    = Deno.env.get("VALR_API_KEY");
  const valrApiSecret = Deno.env.get("VALR_API_SECRET");

  let valrOrderId = `DEV_${params.reference}`;

  if (valrApiKey && valrApiSecret) {
    const order = await buyXrp({
      apiKey:    valrApiKey,
      apiSecret: valrApiSecret,
      zarAmount: zarToBuyWith,
      orderId:   params.reference,
    });
    valrOrderId = order.orderId;
  } else {
    console.log(`[DEV] Would buy ${dcToCredit.toFixed(4)} XRP on VALR for R${zarToBuyWith.toFixed(2)}`);
  }

  // Log FIRST: the unique index on topup references means a replayed webhook
  // fails here (23505) before any money is credited.
  const { error: logErr } = await supabase.from("transactions").insert({
    user_id:    params.userId,
    type:       "topup",
    amount_dc:  dcToCredit,
    amount_zar: params.zarAmount,
    fee_dc:     (appFeeZAR + valrFeeZAR) / xrpPrice,
    status:     "pending",
    reference:  params.reference,
    metadata: {
      provider:       params.provider,
      xrp_price:      xrpPrice,
      app_fee_zar:    appFeeZAR,
      valr_fee_zar:   valrFeeZAR,
      zar_to_exchange: zarToBuyWith,
      valr_order_id:  valrOrderId,
    },
  });
  if (logErr) {
    if ((logErr as any).code === "23505") throw new Error(`Payment ${params.reference} already processed`);
    throw new Error(`Could not record top-up: ${logErr.message}`);
  }

  try {
    await creditBalance(params.userId, dcToCredit);
  } catch (e) {
    await supabase.from("transactions").update({ status: "failed" })
      .eq("reference", params.reference).eq("type", "topup");
    throw e;
  }
  await supabase.from("transactions").update({ status: "completed" })
    .eq("reference", params.reference).eq("type", "topup");

  return { dcCredited: dcToCredit, zarSpent: params.zarAmount };
}

// ── Main handler ──────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Headers": "authorization, x-webhook-signature, content-type",
        "Access-Control-Allow-Methods": "POST, GET",
      },
    });
  }

  // ── GET: bank details + THIS user's personal reference ────────────────────
  // Requires sign-in; the reference comes from the user's own profile row
  // (profiles.topup_ref), never from a query parameter.
  if (req.method === "GET") {
    try {
      const userId = await requireAuth(req);
      const accountNumber = Deno.env.get("BANK_ACCOUNT_NUMBER");
      if (!accountNumber) {
        return new Response(JSON.stringify({ error: "EFT top-up is not available yet." }),
          { status: 503, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } });
      }
      const { data: prof, error } = await adminClient()
        .from("profiles").select("topup_ref").eq("id", userId).single();
      if (error || !prof?.topup_ref) throw new Error("Profile not found");
      const ref = `DLT-${prof.topup_ref}`;
      return new Response(JSON.stringify({
        bank_name:      Deno.env.get("BANK_NAME")           ?? "",
        account_name:   Deno.env.get("BANK_ACCOUNT_NAME")   ?? "",
        account_number: accountNumber,
        branch_code:    Deno.env.get("BANK_BRANCH_CODE")    ?? "",
        account_type:   Deno.env.get("BANK_ACCOUNT_TYPE")   ?? "Current",
        reference:      ref,
        instructions:   [
          "Open your banking app",
          "Add Delight as a beneficiary",
          `Use reference: ${ref}`,
          "Your balance updates within 1 business day",
        ],
      }), { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } });
    } catch (e) {
      return new Response(JSON.stringify({ error: e.message }), {
        status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } });
    }
  }

  // ── POST: webhook from Peach Payments / Ozow when EFT arrives ─────────────
  if (req.method === "POST") {
    const rawBody = await req.text();

    try {
      const webhookSecret = Deno.env.get("WEBHOOK_SECRET");
      const signature     = req.headers.get("x-webhook-signature") ?? "";

      // Verify the webhook is genuinely from our payment provider
      // Fail CLOSED: with no secret configured nobody can credit money.
      if (!webhookSecret) throw new Error("Webhook secret not configured");
      if (!verifyPeachWebhook(rawBody, signature, webhookSecret)) {
        return new Response("Invalid signature", { status: 401 });
      }

      const payload = JSON.parse(rawBody);

      // ── Peach Payments webhook shape ─────────────────────────────────────
      // Different providers have slightly different shapes — adjust as needed
      // Peach: { status: "COMPLETE", amount: 20000, currency: "ZAR",
      //          merchantRef: "DLT-ABCD1234", paymentType: "EFT" }
      // Ozow:  { Status: "Complete", Amount: 200.00, Reference: "DLT-ABCD1234" }

      const status    = payload.status ?? payload.Status;
      const reference = payload.merchantRef ?? payload.Reference ?? payload.reference;

      // Only process completed payments
      if (!["COMPLETE","Complete","completed","PAID"].includes(status)) {
        console.log(`Webhook received but status is ${status} — ignoring`);
        return new Response(JSON.stringify({ received: true }), { status: 200 });
      }

      // Amount in cents (Peach) or rands (Ozow) — normalise to rands
      const zarAmount = payload.amount
        ? payload.amount / 100          // Peach sends cents
        : parseFloat(payload.Amount);  // Ozow sends rands

      if (!zarAmount || zarAmount < MIN_TOPUP_ZAR) {
        throw new Error(`Amount too small: R${zarAmount}`);
      }

      // Match the payer by their personal reference (profiles.topup_ref).
      const supabase     = adminClient();
      const refCode      = String(reference ?? "").replace(/^DLT-/i, "").trim().toUpperCase();
      const { data: profile } = await supabase
        .from("profiles")
        .select("id")
        .eq("topup_ref", refCode)
        .maybeSingle();

      if (!profile) {
        // Payment arrived but can't match user — log it for manual review
        await supabase.from("unmatched_payments").insert({
          reference, zarAmount, payload, received_at: new Date().toISOString()
        });
        console.error(`Unmatched payment: ${reference} for R${zarAmount}`);
        return new Response(JSON.stringify({ received: true, matched: false }), { status: 200 });
      }

      // Process the top-up
      const result = await processConfirmedTopup({
        userId:    profile.id,
        zarAmount,
        reference,
        provider:  "peach",
      });

      // TODO: Send push notification via Firebase
      // await sendPushNotification(profile.id,
      //   `R${zarAmount} added`, `Your wallet now has R${result.dcCredited * xrpPrice} ready to spend`);

      return new Response(JSON.stringify({
        success:    true,
        dc_credited: result.dcCredited,
        zar_topup:  result.zarSpent,
      }), {
        headers: { "Content-Type": "application/json" },
      });

    } catch (e) {
      console.error("Topup webhook error:", e.message);
      if (String(e.message).includes("already processed")) {
        // Replay of a payment we already credited — acknowledge so the provider stops retrying.
        return new Response(JSON.stringify({ success: true, duplicate: true }), { status: 200 });
      }
      return new Response(JSON.stringify({ success: false, error: e.message }), { status: 400 });
    }
  }

  return new Response("Method not allowed", { status: 405 });
});

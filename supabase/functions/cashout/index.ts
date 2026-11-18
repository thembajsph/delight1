// supabase/functions/cashout/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Cash Out: DC → ZAR via EFT to user's SA bank account
//
// Flow:
//   1. User submits cashout request (zarAmount, bankAccount, bankName)
//   2. We verify their DC balance in Supabase
//   3. We deduct the DC immediately (pessimistic — prevents double spend)
//   4. We sell XRP on VALR (market order)
//   5. We trigger a standard EFT to their bank account
//   6. We log the transaction and notify the user
//
// EFT instead of PayShap:
//   - EFT is free — no per-transaction fee eating into the user's 0.5%
//   - Arrives in 1–2 business days (Mon–Fri, before 3PM for same-day)
//   - PayShap charges ~R2–R8 per transaction — defeats the 0.5% promise
//   - Once Flash API is active, agents can give instant cash instead
//
// EFT provider options (pick one — all free for sender):
//   - Peach Payments: peachpayments.com (easiest integration, SA-focused)
//   - Netcash: netcash.co.za (established, good SA bank coverage)
//   - Direct bank API: for high volume, negotiate with ABSA/FNB directly
//
// SECRETS NEEDED (set via: supabase secrets set KEY=value):
//   VALR_API_KEY         — from valr.com → API Keys
//   VALR_API_SECRET      — from valr.com → API Keys
//   EFT_API_KEY          — from Peach Payments / Netcash
//   EFT_API_SECRET       — from Peach Payments / Netcash
//   SUPABASE_URL         — auto-set by Supabase
//   SUPABASE_SERVICE_ROLE_KEY — auto-set by Supabase
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireAuth, getUserWallet, deductBalance, creditBalance, logTransaction, adminClient } from "../_shared/supabase.ts";
import { sellXrp, getXrpPrice }                                                   from "../_shared/valr.ts";

// ── Constants ─────────────────────────────────────────────────────────────────
const APP_FEE_PERCENT  = 0.005;  // 0.5% Delight fee
const NETWORK_FEE_ZAR  = 0.05;  // ~R0.05 XRP network fee
const MIN_CASHOUT_ZAR  = 10.0;  // minimum R10

// ── EFT payout via Peach Payments (or Netcash — same structure) ──────────────
async function sendEftPayout(params: {
  zarAmount:     number;
  accountName:   string;
  accountNumber: string;
  bankName:      string;
  reference:     string;   // what appears on their bank statement
  orderId:       string;
}): Promise<{ success: boolean; eftReference: string }> {

  const apiKey    = Deno.env.get("EFT_API_KEY");
  const apiSecret = Deno.env.get("EFT_API_SECRET");
  const eftUrl    = Deno.env.get("EFT_API_URL") ?? "https://api.peachpayments.com/v1/payouts";

  // ── INTEGRATION NOTE ─────────────────────────────────────────────────────
  // This is the Peach Payments payout API shape.
  // Sign up at: https://peachpayments.com/za/developers
  // Approval: ~2–3 business days + bank account verification
  //
  // For Netcash instead, the body shape changes slightly:
  //   See: https://netcash.co.za/developers/api-documentation/
  //
  // For ABSA/FNB direct:
  //   You need a business account + corporate banking API agreement
  //   Not worth it until you're processing > R500k/month
  // ─────────────────────────────────────────────────────────────────────────
  if (!apiKey || !apiSecret) {
    // Dev mode — log what would happen, don't actually send
    console.log(`[DEV] EFT payout would send R${params.zarAmount.toFixed(2)} to ${params.accountName} (${params.bankName} ${params.accountNumber})`);
    return {
      success:      true,
      eftReference: `DEV_EFT_${params.orderId}`,
    };
  }

  const body = JSON.stringify({
    amount:        Math.round(params.zarAmount * 100), // in cents
    currency:      "ZAR",
    type:          "EFT",
    recipient: {
      name:          params.accountName,
      accountNumber: params.accountNumber,
      bankName:      params.bankName,
      accountType:   "current", // or "savings"
    },
    reference:     params.reference,
    merchantRef:   params.orderId,
  });

  const r = await fetch(eftUrl, {
    method: "POST",
    headers: {
      "Content-Type":  "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body,
  });

  if (!r.ok) {
    const err = await r.text();
    throw new Error(`EFT payout failed: ${r.status} — ${err}`);
  }

  const d = await r.json();
  return {
    success:      true,
    eftReference: d.id ?? params.orderId,
  };
}

// ── Main handler ──────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "POST",
      },
    });
  }

  try {
    // 1. Auth — verify the user is who they say they are
    const userId = await requireAuth(req);

    // 2. Parse request body
    const {
      zarAmount,
      accountName,
      accountNumber,
      bankName,
    } = await req.json() as {
      zarAmount:     number;
      accountName:   string;
      accountNumber: string;
      bankName:      string;
    };

    // 3. Validate inputs
    if (!zarAmount || zarAmount < MIN_CASHOUT_ZAR) {
      throw new Error(`Minimum cashout is R${MIN_CASHOUT_ZAR}`);
    }
    if (!accountName?.trim()) throw new Error("Account holder name is required");
    if (!accountNumber?.trim() || accountNumber.length < 8) {
      throw new Error("Valid account number is required (minimum 8 digits)");
    }
    if (!bankName?.trim()) throw new Error("Bank name is required");

    // 4. Get live XRP price
    const xrpPrice  = await getXrpPrice();

    // 5. Calculate exact amounts
    const appFeeZAR  = zarAmount * APP_FEE_PERCENT;       // 0.5% Delight fee
    const zarAfterFee = zarAmount - appFeeZAR - NETWORK_FEE_ZAR; // user receives this
    const dcToDeduct  = zarAmount / xrpPrice;             // DC leaving wallet
    const xrpToSell   = dcToDeduct;                       // 1:1 DC = XRP

    // 6. Check balance
    const wallet = await getUserWallet(userId);
    if (wallet.balance_dc < dcToDeduct) {
      throw new Error(
        `Insufficient balance. You have ${(wallet.balance_dc * xrpPrice).toFixed(2)} ZAR worth of DC, ` +
        `but need R${zarAmount.toFixed(2)}.`
      );
    }

    // 7. Generate order reference
    const orderId = `DELIGHT_CASHOUT_${userId}_${Date.now()}`;

    // 8. Deduct DC immediately (prevents race conditions / double spend)
    await deductBalance(userId, dcToDeduct);

    // 9. Sell XRP on VALR
    let valrOrderId: string;
    try {
      const valrApiKey    = Deno.env.get("VALR_API_KEY")!;
      const valrApiSecret = Deno.env.get("VALR_API_SECRET")!;
      const result = await sellXrp({
        apiKey: valrApiKey, apiSecret: valrApiSecret,
        xrpAmount: xrpToSell, orderId,
      });
      valrOrderId = result.orderId;
    } catch (e) {
      // VALR sell failed — refund the DC and abort
      // Atomic credit of exactly what we took — never "restore the old
      // balance", which would erase any other transaction made meanwhile.
      await creditBalance(userId, dcToDeduct);
      throw new Error(`Exchange failed: ${e.message}. Your DC has been refunded.`);
    }

    // 10. Send EFT payout (free for user — arrives 1–2 business days)
    const eft = await sendEftPayout({
      zarAmount:     zarAfterFee,
      accountName,
      accountNumber,
      bankName,
      reference:     `Delight ${orderId.slice(-8)}`, // what shows on bank statement
      orderId,
    });

    // 11. Log the transaction in Supabase
    await logTransaction({
      user_id:    userId,
      type:       "cashout",
      amount_dc:  dcToDeduct,
      amount_zar: zarAmount,
      fee_dc:     appFeeZAR / xrpPrice,
      status:     "completed",
      reference:  eft.eftReference,
      metadata: {
        bank_name:      bankName,
        account_number: accountNumber.slice(-4).padStart(accountNumber.length, "*"), // masked
        xrp_price_used: xrpPrice,
        valr_order_id:  valrOrderId,
        eft_reference:  eft.eftReference,
        zar_received:   zarAfterFee,
      },
    });

    // 12. Return success
    return new Response(JSON.stringify({
      success:      true,
      zarAmount:    zarAmount,
      zarReceived:  zarAfterFee,
      fee:          appFeeZAR,
      eftReference: eft.eftReference,
      message:      `R${zarAfterFee.toFixed(2)} is on its way to your ${bankName} account. EFT arrives in 1–2 business days.`,
    }), {
      headers: {
        "Content-Type":               "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });

  } catch (e) {
    console.error("Cashout error:", e.message);
    return new Response(JSON.stringify({ success: false, error: e.message }), {
      status: 400,
      headers: {
        "Content-Type":               "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
});

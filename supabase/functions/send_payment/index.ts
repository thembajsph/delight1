// supabase/functions/send_payment/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Internal P2P payment: DC from sender → DC to recipient
// No VALR, no blockchain — pure Supabase ledger update, instant, near-zero cost
//
// Fee: 0.5% (configurable, matches env.dart)
// ─────────────────────────────────────────────────────────────────────────────

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { requireAuth, getUserWallet, adminClient, logTransaction } from "../_shared/supabase.ts";

const APP_FEE_PERCENT = 0.005;  // 0.5%
const XRP_PRICE       = 9.50;   // fallback — real price fetched in cashout only
const MIN_SEND_ZAR    = 1.0;

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
    const senderId = await requireAuth(req);

    const { recipientPhone, zarAmount, memo } = await req.json() as {
      recipientPhone: string;
      zarAmount:      number;
      memo?:          string;
    };

    if (!zarAmount || zarAmount < MIN_SEND_ZAR) {
      throw new Error(`Minimum send is R${MIN_SEND_ZAR}`);
    }
    if (!recipientPhone?.trim()) throw new Error("Recipient phone is required");

    // Find recipient by phone
    const supabase = adminClient();
    const { data: recipient, error: rErr } = await supabase
      .from("profiles")
      .select("id, display_name")
      .eq("phone", recipientPhone.replace(/\s/g, ""))
      .single();

    if (rErr || !recipient) {
      throw new Error("Recipient not found on Delight. They need to sign up first.");
    }

    if (recipient.id === senderId) {
      throw new Error("You cannot send money to yourself.");
    }

    // Calculate DC amounts
    const dcAmount    = zarAmount / XRP_PRICE;
    const feeDC       = dcAmount * APP_FEE_PERCENT;
    const totalDC     = dcAmount + feeDC;

    // Get sender wallet and check balance
    const senderWallet = await getUserWallet(senderId);
    if (senderWallet.balance_dc < totalDC) {
      throw new Error(
        `Not enough balance. You need R${zarAmount.toFixed(2)} plus fee R${(feeDC * XRP_PRICE).toFixed(2)}.`
      );
    }

    // Get recipient wallet
    const recipientWallet = await getUserWallet(recipient.id);

    // Atomic update — deduct from sender, credit to recipient
    const { error: txErr } = await supabase.rpc("transfer_dc", {
      p_sender_id:    senderId,
      p_recipient_id: recipient.id,
      p_amount_dc:    dcAmount,
      p_fee_dc:       feeDC,
    });

    if (txErr) throw new Error(`Transfer failed: ${txErr.message}`);

    // Log for sender
    await logTransaction({
      user_id:    senderId,
      type:       "send",
      amount_dc:  dcAmount,
      amount_zar: zarAmount,
      fee_dc:     feeDC,
      status:     "completed",
      reference:  `to:${recipient.id}`,
      metadata:   { recipient_name: recipient.display_name, memo },
    });

    // Log for recipient
    await logTransaction({
      user_id:    recipient.id,
      type:       "receive",
      amount_dc:  dcAmount,
      amount_zar: zarAmount,
      fee_dc:     0,
      status:     "completed",
      reference:  `from:${senderId}`,
      metadata:   { memo },
    });

    return new Response(JSON.stringify({
      success:       true,
      zarAmount,
      recipientName: recipient.display_name,
      message:       `R${zarAmount.toFixed(2)} sent to ${recipient.display_name} instantly.`,
    }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });

  } catch (e) {
    return new Response(JSON.stringify({ success: false, error: e.message }), {
      status: 400,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }
});

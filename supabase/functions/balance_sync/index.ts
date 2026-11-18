// supabase/functions/balance_sync/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Custodial model: Delight holds ONE pooled XRPL hot wallet server-side.
// Consumers never have their own on-chain address, so there's nothing to
// "sync from the ledger" per-user — wallets.balance_dc IS the source of
// truth, maintained by topup/cashout/send_payment. This function just
// returns the current ledger balance plus a fresh ZAR price so the app's
// pull-to-refresh has something real to show.
//
// (If you ever add non-custodial/advanced wallets for business/organizer
// accounts with their own xrp_address, re-introduce a real on-chain
// getBalance() call gated on that field being present — never let it
// overwrite a custodial user's ledger balance.)
// ─────────────────────────────────────────────────────────────────────────────

import { serve }            from "https://deno.land/std@0.208.0/http/server.ts";
import { requireAuth, getUserWallet, adminClient } from "../_shared/supabase.ts";
import { getXrpPrice }      from "../_shared/valr.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin":  "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const userId = await requireAuth(req);
    const wallet = await getUserWallet(userId);

    const balanceDC  = wallet.balance_dc ?? 0;
    const xrpPrice    = await getXrpPrice();
    const balanceZAR  = balanceDC * xrpPrice;

    // Just refresh the cached price + timestamp — never touch balance_dc here.
    const supabase = adminClient();
    await supabase.from("wallets").update({
      xrp_price:   xrpPrice,
      last_synced: new Date().toISOString(),
    }).eq("user_id", userId);

    return new Response(JSON.stringify({
      success:     true,
      balance_dc:  balanceDC,
      balance_zar: balanceZAR,
      xrp_price:   xrpPrice,
      xrp_address: wallet.xrp_address ?? null,
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

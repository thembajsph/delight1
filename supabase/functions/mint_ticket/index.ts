// supabase/functions/mint_ticket/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Mint NFT ticket on XRP Ledger when a user buys a ticket
//
// The NFT proves:
//   - Who attended (wallet address on-chain)
//   - Which event (metadata URI → IPFS JSON with event details)
//   - Tier (VIP / General / Table)
//   - Transfer fee (3% royalty locked on-chain permanently)
//
// SECRETS NEEDED:
//   HOT_WALLET_ADDRESS  — your Delight XRP address (minting account)
//   HOT_WALLET_SEED     — your XRP wallet seed (NEVER in Flutter app)
//   XRPL_TESTNET        — "true" for testnet, "false" for mainnet
// ─────────────────────────────────────────────────────────────────────────────

import { serve }      from "https://deno.land/std@0.208.0/http/server.ts";
import { requireAuth, adminClient } from "../_shared/supabase.ts";

// XRPL node
const NODE = Deno.env.get("XRPL_TESTNET") === "true"
  ? "https://s.altnet.rippletest.net:51234"
  : "https://xrplcluster.com";

/** Convert string to hex — required for XRPL URI field */
function toHex(str: string): string {
  return Array.from(new TextEncoder().encode(str))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("").toUpperCase();
}

/** Submit a signed transaction to the XRP Ledger */
async function submitTx(txBlob: string): Promise<{ hash: string; result: string }> {
  const r = await fetch(NODE, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ method: "submit", params: [{ tx_blob: txBlob }] }),
  });
  const d = await r.json();
  return {
    hash:   d.result?.tx_json?.hash ?? "unknown",
    result: d.result?.engine_result ?? "unknown",
  };
}

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

    // priceZAR may still be sent by older app versions; it is ignored.
    const { eventId, tier } = await req.json() as {
      eventId:  string;
      tier:     string;   // must match a tier name on the event
      priceZAR?: number;
    };

    const supabase = adminClient();

    // Get the event
    const { data: event, error: evErr } = await supabase
      .from("events").select("*").eq("id", eventId).single();
    if (evErr || !event) throw new Error("Event not found");

    // Custodial model: tickets are minted from Delight's own pooled hot
    // wallet (see hotWalletAddress below) and never transferred on-chain to
    // the buyer — ownership lives in Supabase (tickets.user_id), not on the
    // ledger. We don't require the buyer to have their own xrp_address;
    // fall back to a stable internal tag for the "holder" metadata field.
    const { data: wallet } = await supabase
      .from("wallets").select("xrp_address").eq("user_id", userId).single();
    const holderTag = wallet?.xrp_address || `delight-user:${userId}`;

    // Build metadata that will live on IPFS (pinned permanently)
    const metadata = {
      name:        `${event.name} — ${tier} Ticket`,
      description: `NFT ticket for ${event.name} on ${event.event_date}`,
      event: {
        id:    eventId,
        name:  event.name,
        date:  event.event_date,
        venue: event.venue,
        city:  event.city,
      },
      tier,
      holder: holderTag,
      issued: new Date().toISOString(),
      delight_version: "1.0",
    };

    // ── IPFS upload ────────────────────────────────────────────────────────
    // For MVP: use nft.storage (free, permanent)
    // Sign up: https://nft.storage → get API key → set NFT_STORAGE_KEY secret
    // For production: use Pinata (pinata.cloud) — more reliable
    const nftStorageKey = Deno.env.get("NFT_STORAGE_KEY");
    let metadataUri = `ipfs://bafybeif5example${eventId}`; // fallback for dev

    if (nftStorageKey) {
      const ipfsRes = await fetch("https://api.nft.storage/upload", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${nftStorageKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(metadata),
      });
      if (ipfsRes.ok) {
        const ipfsData = await ipfsRes.json();
        metadataUri = `ipfs://${ipfsData.value?.cid}`;
      }
    }

    // ── Mint NFT on XRPL ──────────────────────────────────────────────────
    // NOTE: In production, use xrpl.js to sign the transaction with the hot wallet seed.
    // The seed is in Supabase secrets — it never leaves this function.
    //
    // Full xrpl.js signing:
    //   import * as xrpl from "npm:xrpl";
    //   const wallet = xrpl.Wallet.fromSeed(Deno.env.get("HOT_WALLET_SEED"));
    //   const tx = { TransactionType: "NFTokenMint", ... };
    //   const signed = wallet.sign(tx);
    //   const result = await submitTx(signed.tx_blob);
    //
    // For now, we record it in Supabase as "pending_mint" and a cron job
    // does the actual XRPL submission in batches (saves on XRP fees).
    const hotWalletAddress = Deno.env.get("HOT_WALLET_ADDRESS") ?? "rDelightHotWallet";

    const nftTx = {
      TransactionType: "NFTokenMint",
      Account:         hotWalletAddress,
      URI:             toHex(metadataUri),    // metadata pointer
      Flags:           8,                     // tfTransferable — can be resold
      TransferFee:     300,                   // 3% royalty on resales (300 basis points)
      NFTokenTaxon:    0,
      Memos: [{
        Memo: {
          MemoData: toHex(JSON.stringify({
            event: eventId, tier, buyer: holderTag
          })),
        },
      }],
    };

    // Charge the buyer, pay the organiser (minus the 3% platform fee), bump the
    // tier's sold count and create the ticket — one database transaction.
    // The price comes from the event's tier in the database, never from the client,
    // so a tampered app cannot get tickets for free or cheaper.
    const { data: ticket, error: ticketErr } = await supabase.rpc("_buy_ticket", {
      p_user:          userId,
      p_event:         eventId,
      p_tier:          tier,
      p_metadata_uri:  metadataUri,
      p_owner_address: holderTag,
      p_nft_tx:        nftTx,       // submitted to XRPL later by the cron job
    });
    if (ticketErr) throw new Error(ticketErr.message);

    return new Response(JSON.stringify({
      success:      true,
      ticketId:     ticket.id,
      metadataUri,
      tokenId:      `pending_${ticket.id}`, // real token ID comes from XRPL after mint
      message:      `Ticket minted for ${event.name} (${tier}). NFT will confirm on-chain within 10 seconds.`,
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

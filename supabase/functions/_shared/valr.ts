// supabase/functions/_shared/valr.ts
// VALR Exchange API — shared across edge functions
// Docs: https://docs.valr.com

import { createHmac } from "npm:crypto";

const VALR_BASE = "https://api.valr.com";
const PAIR      = "XRPZAR";

function sign(apiSecret: string, timestamp: string, verb: string, path: string, body = "") {
  const payload = `${timestamp}${verb}${path}${body}`;
  return createHmac("sha512", apiSecret).update(payload).digest("hex");
}

function headers(apiKey: string, apiSecret: string, verb: string, path: string, body = "") {
  const ts = Date.now().toString();
  return {
    "Content-Type":    "application/json",
    "X-VALR-API-KEY":  apiKey,
    "X-VALR-SIGNATURE": sign(apiSecret, ts, verb, path, body),
    "X-VALR-TIMESTAMP": ts,
  };
}

/** Get live XRP/ZAR price */
export async function getXrpPrice(): Promise<number> {
  const r = await fetch(`${VALR_BASE}/v1/public/${PAIR}/marketsummary`);
  if (!r.ok) throw new Error(`VALR price fetch failed: ${r.status}`);
  const d = await r.json();
  return parseFloat(d.lastTradedPrice);
}

/** Sell XRP for ZAR (market order) — used in cashout flow */
export async function sellXrp(params: {
  apiKey: string;
  apiSecret: string;
  xrpAmount: number;   // amount of XRP to sell
  orderId: string;     // your internal reference
}): Promise<{ orderId: string; status: string }> {
  const path = "/v1/orders/market";
  const body = JSON.stringify({
    side:            "SELL",
    baseAmount:      params.xrpAmount.toFixed(6),
    pair:            PAIR,
    postOnly:        false,
    customerOrderId: params.orderId,
  });

  const r = await fetch(`${VALR_BASE}${path}`, {
    method:  "POST",
    headers: headers(params.apiKey, params.apiSecret, "POST", path, body),
    body,
  });

  if (!r.ok) {
    const err = await r.text();
    throw new Error(`VALR sell failed: ${r.status} — ${err}`);
  }

  const d = await r.json();
  return { orderId: d.id ?? params.orderId, status: "placed" };
}

/** Buy XRP with ZAR (market order) — used in top-up flow */
export async function buyXrp(params: {
  apiKey: string;
  apiSecret: string;
  zarAmount: number;   // ZAR to spend
  orderId: string;
}): Promise<{ orderId: string; status: string }> {
  const path = "/v1/orders/market";
  const body = JSON.stringify({
    side:            "BUY",
    quoteAmount:     params.zarAmount.toFixed(2),
    pair:            PAIR,
    postOnly:        false,
    customerOrderId: params.orderId,
  });

  const r = await fetch(`${VALR_BASE}${path}`, {
    method:  "POST",
    headers: headers(params.apiKey, params.apiSecret, "POST", path, body),
    body,
  });

  if (!r.ok) {
    const err = await r.text();
    throw new Error(`VALR buy failed: ${r.status} — ${err}`);
  }

  const d = await r.json();
  return { orderId: d.id ?? params.orderId, status: "placed" };
}

/** Get VALR ZAR wallet balance */
export async function getZarBalance(params: { apiKey: string; apiSecret: string }): Promise<number> {
  const path = "/v1/account/balances";
  const r = await fetch(`${VALR_BASE}${path}`, {
    headers: headers(params.apiKey, params.apiSecret, "GET", path),
  });
  if (!r.ok) throw new Error(`VALR balance fetch failed: ${r.status}`);
  const balances = await r.json() as Array<{ currency: string; available: string }>;
  const zar = balances.find(b => b.currency === "ZAR");
  return parseFloat(zar?.available ?? "0");
}

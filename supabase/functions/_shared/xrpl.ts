// supabase/functions/_shared/xrpl.ts
// XRP Ledger HTTP API — used to check balances and submit transactions
// Docs: https://xrpl.org/http-websocket-apis.html

const MAINNET = "https://xrplcluster.com";
const TESTNET = "https://s.altnet.rippletest.net:51234";

const NODE = Deno.env.get("XRPL_TESTNET") === "true" ? TESTNET : MAINNET;

/** Get XRP balance for an address in XRP (not drops) */
export async function getBalance(address: string): Promise<number> {
  const r = await fetch(NODE, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      method: "account_info",
      params: [{ account: address, ledger_index: "validated" }],
    }),
  });

  if (!r.ok) throw new Error(`XRPL request failed: ${r.status}`);
  const d = await r.json();

  if (d.result?.error) {
    if (d.result.error === "actNotFound") return 0; // account not activated yet
    throw new Error(`XRPL error: ${d.result.error}`);
  }

  const drops = parseInt(d.result.account_data.Balance);
  return drops / 1_000_000; // convert drops → XRP
}

/** Get recent transactions for an address */
export async function getTransactions(address: string, limit = 20): Promise<XrplTx[]> {
  const r = await fetch(NODE, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      method: "account_tx",
      params: [{ account: address, limit, ledger_index_min: -1, ledger_index_max: -1 }],
    }),
  });

  if (!r.ok) return [];
  const d = await r.json();
  return d.result?.transactions ?? [];
}

export interface XrplTx {
  tx: {
    TransactionType: string;
    Account: string;
    Destination?: string;
    Amount?: string | object;
    hash: string;
    date: number;
  };
  meta: { TransactionResult: string };
}

// supabase/functions/_shared/supabase.ts
// Supabase admin client for edge functions (bypasses RLS)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export function adminClient() {
  const url     = Deno.env.get("SUPABASE_URL")!;
  const service  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, service, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** Verify JWT and return user_id — call this first in every function */
export async function requireAuth(req: Request): Promise<string> {
  const token = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!token) throw new Error("Missing authorization header");

  const supabase = adminClient();
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) throw new Error("Invalid token");
  return user.id;
}

/** Get user's wallet record from DB */
export async function getUserWallet(userId: string) {
  const supabase = adminClient();
  const { data, error } = await supabase
    .from("wallets")
    .select("*")
    .eq("user_id", userId)
    .single();
  if (error) throw new Error(`Wallet not found: ${error.message}`);
  return data;
}

/** Deduct balance atomically (fails if insufficient). */
export async function deductBalance(userId: string, dcAmount: number) {
  const { error } = await adminClient().rpc("debit_wallet", { p_user: userId, p_dc: dcAmount });
  if (error) throw new Error(`Balance deduction failed: ${error.message}`);
}

/** Credit balance atomically — safe when two credits land at the same time. */
export async function creditBalance(userId: string, dcAmount: number) {
  const { error } = await adminClient().rpc("credit_wallet", { p_user: userId, p_dc: dcAmount });
  if (error) throw new Error(`Balance credit failed: ${error.message}`);
}

/** Log a transaction to the transactions table */
export async function logTransaction(tx: {
  user_id: string;
  type: string;           // 'cashout' | 'topup' | 'send' | 'receive' | 'ticket_purchase'
  amount_dc: number;
  amount_zar: number;
  fee_dc: number;
  status: string;         // 'pending' | 'completed' | 'failed'
  reference?: string;     // VALR order ID, EFT reference, etc.
  metadata?: object;
}) {
  const supabase = adminClient();
  const { error } = await supabase.from("transactions").insert(tx);
  if (error) throw new Error(`Transaction log failed: ${error.message}`);
}

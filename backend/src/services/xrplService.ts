// backend/src/services/xrplService.ts
// Real XRP Ledger integration for the backend.
// Handles: send XRP, mint NFT tickets, monitor transactions.

import * as xrpl from 'xrpl';
import { logger } from './logger';

const NETWORK = process.env.XRPL_NETWORK === 'mainnet'
  ? process.env.XRPL_MAINNET_WS!
  : process.env.XRPL_TESTNET_WS!;

let client: xrpl.Client | null = null;

async function getClient(): Promise<xrpl.Client> {
  if (!client || !client.isConnected()) {
    client = new xrpl.Client(NETWORK);
    await client.connect();
    logger.info(`XRPL connected to ${NETWORK}`);
  }
  return client;
}

// ── Get live balance ──────────────────────────────────────────────────────────

export async function getBalance(address: string): Promise<number> {
  const c = await getClient();
  try {
    const response = await c.request({
      command: 'account_info',
      account: address,
      ledger_index: 'current',
    });
    // Balance in drops → XRP (1 XRP = 1,000,000 drops)
    return Number(response.result.account_data.Balance) / 1_000_000;
  } catch (err: any) {
    if (err.data?.error === 'actNotFound') return 0; // Not yet funded
    throw err;
  }
}

// ── Send XRP payment ──────────────────────────────────────────────────────────

export async function sendXRP({
  fromSecret,
  toAddress,
  amountXRP,
  memo,
}: {
  fromSecret: string;
  toAddress: string;
  amountXRP: number;
  memo?: string;
}): Promise<{ txHash: string; result: string }> {
  const c = await getClient();
  const wallet = xrpl.Wallet.fromSeed(fromSecret);

  // Convert XRP to drops (string required by XRPL)
  const amountDrops = xrpl.xrpToDrops(amountXRP.toFixed(6));

  const tx: xrpl.Payment = {
    TransactionType: 'Payment',
    Account: wallet.address,
    Destination: toAddress,
    Amount: amountDrops,
    ...(memo && {
      Memos: [{
        Memo: {
          MemoData: Buffer.from(memo, 'utf8').toString('hex').toUpperCase(),
        },
      }],
    }),
  };

  const prepared = await c.autofill(tx);
  const signed = wallet.sign(prepared);
  const result = await c.submitAndWait(signed.tx_blob);

  const engineResult = (result.result.meta as any)?.TransactionResult ?? 'unknown';
  if (engineResult !== 'tesSUCCESS') {
    throw new Error(`Transaction failed: ${engineResult}`);
  }

  logger.info(`XRP sent: ${amountXRP} XRP to ${toAddress} — ${signed.hash}`);
  return { txHash: signed.hash, result: engineResult };
}

// ── Mint NFT Ticket ────────────────────────────────────────────────────────────

export async function mintNFTTicket({
  organizerSecret,
  eventId,
  tierId,
  metadataUrl,
  transferFee = 300,  // 3% royalty on resales (300 = 3% in basis points / 10)
}: {
  organizerSecret: string;
  eventId: string;
  tierId: string;
  metadataUrl: string;
  transferFee?: number;
}): Promise<{ tokenId: string; txHash: string }> {
  const c = await getClient();
  const wallet = xrpl.Wallet.fromSeed(organizerSecret);

  const uriHex = Buffer.from(metadataUrl, 'utf8').toString('hex').toUpperCase();

  const tx: xrpl.NFTokenMint = {
    TransactionType: 'NFTokenMint',
    Account: wallet.address,
    NFTokenTaxon: 1,          // All Delight tickets use taxon 1
    TransferFee: transferFee, // 3% resale royalty
    URI: uriHex,
    Flags: xrpl.NFTokenMintFlags.tfTransferable, // Ticket can be resold
  };

  const prepared = await c.autofill(tx);
  const signed = wallet.sign(prepared);
  const result = await c.submitAndWait(signed.tx_blob);

  // Extract the new NFTokenID from the metadata
  const meta = result.result.meta as any;
  const nftNodes = meta?.AffectedNodes?.filter(
    (n: any) => n.CreatedNode?.LedgerEntryType === 'NFTokenPage'
  ) ?? [];

  const newTokens = meta?.nftoken_id ?? nftNodes[0]?.CreatedNode?.NewFields?.NFTokens?.[0]?.NFToken?.NFTokenID;
  const tokenId = newTokens ?? `NFT_${eventId.slice(-3).toUpperCase()}_${Date.now()}`;

  logger.info(`NFT minted: ${tokenId} for event ${eventId}`);
  return { tokenId, txHash: signed.hash };
}

// ── Transfer NFT Ticket (for resale) ─────────────────────────────────────────

export async function transferNFT({
  fromSecret,
  toAddress,
  tokenId,
  priceXRP,
}: {
  fromSecret: string;
  toAddress: string;
  tokenId: string;
  priceXRP: number;
}): Promise<string> {
  const c = await getClient();
  const wallet = xrpl.Wallet.fromSeed(fromSecret);

  // Create NFT sell offer
  const offerTx: xrpl.NFTokenCreateOffer = {
    TransactionType: 'NFTokenCreateOffer',
    Account: wallet.address,
    NFTokenID: tokenId,
    Amount: xrpl.xrpToDrops(priceXRP.toFixed(6)),
    Destination: toAddress,
    Flags: xrpl.NFTokenCreateOfferFlags.tfSellNFToken,
  };

  const prepared = await c.autofill(offerTx);
  const signed = wallet.sign(prepared);
  const result = await c.submitAndWait(signed.tx_blob);

  logger.info(`NFT transfer offer created: ${tokenId}`);
  return signed.hash;
}

// ── Monitor incoming payments (for USSD / PayShap top-ups) ───────────────────

export async function monitorIncomingPayments(
  address: string,
  callback: (payment: { fromAddress: string; amountXRP: number; txHash: string; memo?: string }) => void
): Promise<void> {
  const c = await getClient();

  await c.request({
    command: 'subscribe',
    accounts: [address],
  });

  c.on('transaction', (event) => {
    const tx = event.transaction as xrpl.Payment;
    if (
      tx.TransactionType === 'Payment' &&
      tx.Destination === address &&
      typeof tx.Amount === 'string'
    ) {
      const amountXRP = Number(tx.Amount) / 1_000_000;
      const memo = tx.Memos?.[0]?.Memo?.MemoData
        ? Buffer.from(tx.Memos[0].Memo.MemoData, 'hex').toString('utf8')
        : undefined;

      callback({
        fromAddress: tx.Account,
        amountXRP,
        txHash: (tx as any).hash ?? '',
        memo,
      });
    }
  });
}

// ── Get transaction history ────────────────────────────────────────────────────

export async function getAccountTransactions(
  address: string,
  limit = 20
): Promise<xrpl.AccountTxTransaction[]> {
  const c = await getClient();
  const response = await c.request({
    command: 'account_tx',
    account: address,
    limit,
    binary: false,
  });
  return response.result.transactions;
}

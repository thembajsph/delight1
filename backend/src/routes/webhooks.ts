// backend/src/routes/webhooks.ts
// ─────────────────────────────────────────────────────────────────────────────
// Webhook handlers:
//   POST /webhooks/ozow   — Ozow fires this when ZAR payment confirmed
//   POST /webhooks/stitch — Stitch fires this when PayShap payment confirmed
//
// FLOW on Ozow webhook:
//   1. Verify Ozow signature
//   2. Look up pending top-up by reference
//   3. Buy XRP on VALR with the ZAR amount
//   4. Send XRP to user's XRPL wallet
//   5. Update Supabase: credit user balance, mark top-up complete
//   6. Push notification to user's phone via Firebase
// ─────────────────────────────────────────────────────────────────────────────

import { Router } from 'express';
import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';
import * as admin from 'firebase-admin';
import { buyXRP, getXrpPriceZAR } from '../services/valrService';
import { sendXRP } from '../services/xrplService';
import { logger } from '../services/logger';

export const webhookRouter = Router();

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

// ── Ozow Webhook ─────────────────────────────────────────────────────────────
webhookRouter.post('/ozow', async (req, res) => {
  // Ozow sends form-encoded data, not JSON
  const body = req.body as Record<string, string>;

  logger.info('Ozow webhook received', { status: body.Status, ref: body.TransactionReference });

  // ── Step 1: Verify Ozow hash ──────────────────────────────────────────────
  const receivedHash = body.Hash?.toLowerCase();
  const fields = [
    body.SiteCode, body.TransactionId, body.TransactionReference,
    body.Amount, body.Status, body.Optional1, body.Optional2, body.Optional3,
    body.Optional4, body.Optional5,
  ].filter(Boolean).join('').toLowerCase() + process.env.OZOW_PRIVATE_KEY!.toLowerCase();

  const expectedHash = crypto.createHash('sha512').update(fields).digest('hex');

  if (receivedHash !== expectedHash) {
    logger.warn('Ozow webhook: invalid hash — possible fraud attempt');
    return res.status(200).send('ok'); // Always 200 to Ozow, but don't process
  }

  // ── Step 2: Only process completed payments ───────────────────────────────
  if (body.Status !== 'Complete') {
    logger.info(`Ozow payment not complete: ${body.Status}`);
    return res.status(200).send('ok');
  }

  const ref = body.TransactionReference;
  const zarAmount = parseFloat(body.Amount);
  const userId = body.Optional1;

  try {
    // ── Step 3: Check not already processed (idempotency) ─────────────────
    const { data: existing } = await supabase
      .from('topups')
      .select('status, xrp_address')
      .eq('reference', ref)
      .single();

    if (!existing || existing.status === 'completed') {
      logger.warn(`Top-up ${ref} already processed or not found`);
      return res.status(200).send('ok');
    }

    const userXrpAddress = existing.xrp_address;

    // ── Step 4: Buy XRP on VALR ───────────────────────────────────────────
    logger.info(`Buying XRP with R${zarAmount} on VALR for user ${userId}`);
    await buyXRP(zarAmount, `TOPUP_${ref}`);

    // Calculate XRP amount (get fresh price after buy)
    const xrpPrice = await getXrpPriceZAR();
    const ozowFee = zarAmount * 0.015;       // Ozow takes 1.5%
    const valrFee = (zarAmount - ozowFee) * 0.001;  // VALR takes 0.1%
    const zarForXrp = zarAmount - ozowFee - valrFee;
    const xrpAmount = parseFloat((zarForXrp / xrpPrice).toFixed(6));

    // ── Step 5: Send XRP to user's wallet ────────────────────────────────
    logger.info(`Sending ${xrpAmount} XRP to ${userXrpAddress}`);
    const { txHash } = await sendXRP({
      fromSecret: process.env.PLATFORM_XRP_SECRET!,
      toAddress: userXrpAddress,
      amountXRP: xrpAmount,
      memo: `Delight top-up R${zarAmount}`,
    });

    // ── Step 6: Update Supabase ───────────────────────────────────────────
    await supabase.from('topups').update({
      status: 'completed',
      xrp_amount: xrpAmount,
      xrp_price_zar: xrpPrice,
      tx_hash: txHash,
      completed_at: new Date().toISOString(),
    }).eq('reference', ref);

    // Update user XRP balance in profile
    const { data: profile } = await supabase
      .from('profiles').select('xrp_balance').eq('id', userId).single();
    const newBalance = (parseFloat(profile?.xrp_balance ?? '0')) + xrpAmount;
    await supabase.from('profiles')
      .update({ xrp_balance: newBalance })
      .eq('id', userId);

    // Save transaction record
    await supabase.from('transactions').insert({
      user_id: userId,
      type: 'topup',
      from_address: 'ozow_eft',
      to_address: userXrpAddress,
      amount_xrp: xrpAmount,
      amount_zar: zarAmount,
      fee_xrp: 0,
      memo: `Top up via Ozow — Ref: ${ref}`,
      status: 'confirmed',
      tx_hash: txHash,
    });

    // ── Step 7: Push notification ─────────────────────────────────────────
    const { data: fcmData } = await supabase
      .from('profiles').select('fcm_token').eq('id', userId).single();

    if (fcmData?.fcm_token) {
      await admin.messaging().send({
        token: fcmData.fcm_token,
        notification: {
          title: '💚 Money Added!',
          body: `R${zarAmount.toFixed(0)} → ${xrpAmount.toFixed(2)} XRP in your Delight wallet`,
        },
        data: { type: 'topup', xrp_amount: xrpAmount.toString() },
      });
    }

    logger.info(`Top-up complete: ${xrpAmount} XRP credited to ${userId} — tx: ${txHash}`);
    res.status(200).send('ok');

  } catch (err: any) {
    logger.error('Ozow webhook processing failed', { err: err.message, ref });
    // Mark as failed so it can be retried
    await supabase.from('topups').update({ status: 'failed', error: err.message }).eq('reference', ref);
    res.status(200).send('ok'); // Still 200 to Ozow — handle retry internally
  }
});

// ── Stitch / PayShap Webhook ─────────────────────────────────────────────────
webhookRouter.post('/stitch', async (req, res) => {
  const body = JSON.parse(req.body.toString());

  // Verify Stitch webhook signature
  const signature = req.headers['stitch-signature'] as string;
  const expected = crypto
    .createHmac('sha256', process.env.WEBHOOK_SECRET!)
    .update(req.body)
    .digest('hex');

  if (`sha256=${expected}` !== signature) {
    logger.warn('Stitch webhook: invalid signature');
    return res.status(401).json({ error: 'Invalid signature' });
  }

  if (body.type !== 'payment.completed') {
    return res.status(200).json({ received: true });
  }

  const { reference, amount, currency } = body.data;
  logger.info(`PayShap payment confirmed: ${currency} ${amount} — ref: ${reference}`);

  // Same flow as Ozow from step 3 onwards
  // (extracted to shared function in production)
  res.status(200).json({ received: true });
});

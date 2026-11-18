// backend/src/routes/topup.ts
import { Router } from 'express';
import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';
import { buyXRP, getXrpPriceZAR } from '../services/valrService';
import { sendXRP } from '../services/xrplService';
import { logger } from '../services/logger';

export const topupRouter = Router();

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

// ── Initiate top-up — returns payment URL ────────────────────────────────────
topupRouter.post('/initiate', async (req, res) => {
  try {
    const { user_id, amount_zar, gateway } = req.body;
    if (!user_id || !amount_zar || amount_zar < 10) {
      return res.status(400).json({ error: 'Invalid request' });
    }

    // Get user wallet address
    const { data: profile } = await supabase
      .from('profiles').select('xrp_address').eq('id', user_id).single();
    if (!profile?.xrp_address) {
      return res.status(400).json({ error: 'Wallet not set up' });
    }

    const ref = `DELIGHT_${user_id.slice(0, 8)}_${Date.now()}`;

    // Save pending top-up
    await supabase.from('topups').insert({
      user_id, amount_zar, gateway, reference: ref,
      status: 'pending', xrp_address: profile.xrp_address,
    });

    let payment_url = '';

    if (gateway === 'ozow') {
      const params: Record<string, string> = {
        SiteCode: process.env.OZOW_SITE_CODE!,
        CountryCode: 'ZA',
        CurrencyCode: 'ZAR',
        Amount: parseFloat(amount_zar).toFixed(2),
        TransactionReference: ref,
        BankReference: 'Delight Top Up',
        Optional1: user_id,
        NotifyUrl: `${process.env.API_BASE_URL}/webhooks/ozow`,
        SuccessUrl: `${process.env.API_BASE_URL}/topup/success`,
        ErrorUrl: `${process.env.API_BASE_URL}/topup/error`,
        CancelUrl: `${process.env.API_BASE_URL}/topup/cancel`,
        IsTest: process.env.NODE_ENV !== 'production' ? 'true' : 'false',
      };
      const hashStr = Object.values(params).join('').toLowerCase()
        + process.env.OZOW_PRIVATE_KEY!.toLowerCase();
      params.HashCheck = crypto.createHash('sha512').update(hashStr).digest('hex');
      payment_url = `https://pay.ozow.com/?${new URLSearchParams(params)}`;

    } else if (gateway === 'moonpay') {
      payment_url = `https://buy.moonpay.com?apiKey=${process.env.MOONPAY_KEY}`
        + `&currencyCode=xrp&baseCurrencyCode=zar&baseCurrencyAmount=${amount_zar}`
        + `&walletAddress=${profile.xrp_address}&colorCode=%2300C96A&theme=dark`;
    }

    res.json({ payment_url, transaction_ref: ref, expires_at: new Date(Date.now() + 30 * 60000) });
  } catch (err: any) {
    logger.error('topup/initiate error', { err: err.message });
    res.status(500).json({ error: 'Failed to initiate payment' });
  }
});

// ── Cash out — XRP → ZAR → SA bank ──────────────────────────────────────────
topupRouter.post('/cashout', async (req, res) => {
  try {
    const { user_id, xrp_amount, bank_account, bank_name } = req.body;
    if (!user_id || !xrp_amount || xrp_amount < 1) {
      return res.status(400).json({ error: 'Minimum cash out is 1 XRP' });
    }

    const price = await getXrpPriceZAR();
    const zarAmount = xrp_amount * price * 0.999; // VALR 0.1% fee

    // Sell XRP on VALR
    await sellXRP(xrp_amount, `CASHOUT_${user_id}_${Date.now()}`);

    // TODO: Send ZAR to user's bank via PayShap (Stitch API)
    // For now log and confirm
    logger.info(`Cash out: ${xrp_amount} XRP → R${zarAmount.toFixed(2)} for ${user_id}`);

    await supabase.from('cashouts').insert({
      user_id, xrp_amount, zar_amount: zarAmount,
      bank_account, bank_name, status: 'processing',
    });

    res.json({
      zar_amount: zarAmount.toFixed(2),
      estimated_arrival: 'Under 60 seconds',
      transaction_id: `CO_${Date.now()}`,
    });
  } catch (err: any) {
    logger.error('cashout error', { err: err.message });
    res.status(500).json({ error: 'Cash out failed' });
  }
});

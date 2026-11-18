// backend/src/routes/wallet.ts
import { Router } from 'express';
import { getBalance, getAccountTransactions } from '../services/xrplService';
export const walletRouter = Router();

walletRouter.get('/balance/:address', async (req, res) => {
  try {
    const balance = await getBalance(req.params.address);
    res.json({ address: req.params.address, balance_xrp: balance });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

walletRouter.get('/transactions/:address', async (req, res) => {
  try {
    const txns = await getAccountTransactions(req.params.address, 20);
    res.json({ transactions: txns });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

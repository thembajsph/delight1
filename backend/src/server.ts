// backend/src/server.ts
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';
import { walletRouter } from './routes/wallet';
import { topupRouter } from './routes/topup';
import { webhookRouter } from './routes/webhooks';
import { eventsRouter } from './routes/events';
import { priceRouter } from './routes/price';
import { logger } from './services/logger';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*' }));

// Raw body for webhook signature verification (Ozow requires raw body)
app.use('/webhooks', express.raw({ type: 'application/json' }));
app.use(express.json());

// Rate limiting
app.use('/api', rateLimit({
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max: 100,
  message: { error: 'Too many requests' },
}));

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/wallet', walletRouter);
app.use('/api/topup',  topupRouter);
app.use('/webhooks',   webhookRouter);
app.use('/api/events', eventsRouter);
app.use('/api/price',  priceRouter);

// Health check
app.get('/health', (_, res) => res.json({
  status: 'ok',
  network: process.env.XRPL_NETWORK || 'testnet',
  version: '1.0.0',
}));

// ── Error handler ─────────────────────────────────────────────────────────────
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  logger.error(err.message, { stack: err.stack, path: req.path });
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  logger.info(`Delight backend running on port ${PORT}`);
  logger.info(`XRPL Network: ${process.env.XRPL_NETWORK || 'testnet'}`);
});

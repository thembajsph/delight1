// backend/src/routes/price.ts
import { Router } from 'express';
import { getXrpPriceZAR } from '../services/valrService';
export const priceRouter = Router();

let cached = { price: 9.50, ts: 0 };

priceRouter.get('/xrp', async (_req, res) => {
  try {
    if (Date.now() - cached.ts > 30000) { // refresh every 30s
      cached.price = await getXrpPriceZAR();
      cached.ts = Date.now();
    }
    res.json({ xrp_zar: cached.price, updated_at: new Date(cached.ts).toISOString() });
  } catch {
    res.json({ xrp_zar: 9.50 });
  }
});

// backend/src/routes/events.ts — placeholder
import { Router as ERouter } from 'express';
export const eventsRouter = ERouter();
eventsRouter.get('/', (_req, res) => res.json({ events: [] }));

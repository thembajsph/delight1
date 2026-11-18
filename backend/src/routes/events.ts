import { Router } from 'express';
export const eventsRouter = Router();
eventsRouter.get('/', (_req, res) => res.json({ events: [] }));

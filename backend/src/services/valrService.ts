// backend/src/services/valrService.ts
import crypto from 'crypto';
import axios from 'axios';
import { logger } from './logger';

const BASE = 'https://api.valr.com';
const KEY = process.env.VALR_API_KEY!;
const SECRET = process.env.VALR_API_SECRET!;

function sign(timestamp: string, verb: string, path: string, body = '') {
  const payload = `${timestamp}${verb}${path}${body}`;
  return crypto.createHmac('sha512', SECRET).update(payload).digest('hex');
}

function headers(verb: string, path: string, body = '') {
  const ts = Date.now().toString();
  return {
    'X-VALR-API-KEY': KEY,
    'X-VALR-SIGNATURE': sign(ts, verb, path, body),
    'X-VALR-TIMESTAMP': ts,
    'Content-Type': 'application/json',
  };
}

export async function getXrpPriceZAR(): Promise<number> {
  const { data } = await axios.get(`${BASE}/v1/public/XRPZAR/marketsummary`);
  return parseFloat(data.lastTradedPrice);
}

export async function buyXRP(zarAmount: number, orderId: string) {
  const path = '/v1/orders/market';
  const body = JSON.stringify({
    side: 'BUY',
    quoteAmount: zarAmount.toFixed(2),
    pair: 'XRPZAR',
    postOnly: false,
    customerOrderId: orderId,
  });
  const { data } = await axios.post(`${BASE}${path}`, body, { headers: headers('POST', path, body) });
  logger.info(`VALR buy order placed: ${orderId}`);
  return data;
}

export async function sellXRP(xrpAmount: number, orderId: string) {
  const path = '/v1/orders/market';
  const body = JSON.stringify({
    side: 'SELL',
    baseAmount: xrpAmount.toFixed(6),
    pair: 'XRPZAR',
    postOnly: false,
    customerOrderId: orderId,
  });
  const { data } = await axios.post(`${BASE}${path}`, body, { headers: headers('POST', path, body) });
  logger.info(`VALR sell order placed: ${orderId}`);
  return data;
}

export async function getBalance(currency: 'ZAR' | 'XRP') {
  const path = '/v1/account/balances';
  const { data } = await axios.get(`${BASE}${path}`, { headers: headers('GET', path) });
  const bal = data.find((b: any) => b.currency === currency);
  return parseFloat(bal?.available ?? '0');
}

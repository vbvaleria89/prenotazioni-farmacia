import { handleGcalOauthCallback } from '../netlify/functions/_shared/gcal.mjs';
export const POST = (req) => handleGcalOauthCallback(req);
export const GET = (req) => handleGcalOauthCallback(req);
export const OPTIONS = (req) => handleGcalOauthCallback(req);

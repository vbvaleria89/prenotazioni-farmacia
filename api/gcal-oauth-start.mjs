import { handleGcalOauthStart } from '../netlify/functions/_shared/gcal.mjs';
export const POST = (req) => handleGcalOauthStart(req);
export const GET = (req) => handleGcalOauthStart(req);
export const OPTIONS = (req) => handleGcalOauthStart(req);

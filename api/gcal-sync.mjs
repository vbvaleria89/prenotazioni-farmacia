import { handleGcalSync } from '../netlify/functions/_shared/gcal.mjs';
export const POST = (req) => handleGcalSync(req);
export const GET = (req) => handleGcalSync(req);
export const OPTIONS = (req) => handleGcalSync(req);

import { handleGcalPushColors } from '../netlify/functions/_shared/gcal.mjs';
export const POST = (req) => handleGcalPushColors(req);
export const OPTIONS = (req) => handleGcalPushColors(req);

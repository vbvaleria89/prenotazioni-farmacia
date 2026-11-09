import { handleGcalStatus } from '../netlify/functions/_shared/gcal.mjs';
export const POST = (req) => handleGcalStatus(req);
export const GET = (req) => handleGcalStatus(req);
export const OPTIONS = (req) => handleGcalStatus(req);

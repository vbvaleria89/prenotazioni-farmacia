import { handleGcalReconcile } from '../netlify/functions/_shared/gcal.mjs';
export const POST = (req) => handleGcalReconcile(req);
export const GET = (req) => handleGcalReconcile(req);
export const OPTIONS = (req) => handleGcalReconcile(req);

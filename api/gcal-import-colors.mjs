import { handleGcalImportColors } from '../netlify/functions/_shared/gcal.mjs';
export const POST = (req) => handleGcalImportColors(req);
export const OPTIONS = (req) => handleGcalImportColors(req);

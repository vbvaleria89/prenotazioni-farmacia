// Vercel Function (Web Request/Response) — riusa la logica Netlify.
import handler from '../netlify/functions/create-employee.mjs';
export const POST = (req) => handler(req);
export const OPTIONS = (req) => handler(req);
export const GET = (req) => handler(req);

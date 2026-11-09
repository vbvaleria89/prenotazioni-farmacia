import handler from '../netlify/functions/send-assignment.mjs';
export const POST = (req) => handler(req);
export const GET = (req) => handler(req);

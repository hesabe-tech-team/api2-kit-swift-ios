// The demo app's backend. This process is the only place the merchant keys exist:
// the app receives a session's `data` string and nothing else.
//
//   npm install && npm start
//
// Built on node:http with no framework, so the two handlers are the whole story.

import { createServer } from "node:http";
import { Hesabe, HesabeError, isSuccessful } from "hesabe";

const PORT = Number(process.env.PORT ?? 4242);

// Hesabe's published sandbox keys. Yours come from Merchant Panel, Profile, Merchant
// Keys, through the environment, and never reach the app.
const hesabe = new Hesabe({
  merchantCode: process.env.HESABE_MERCHANT_CODE ?? "842217",
  accessCode: process.env.HESABE_ACCESS_CODE ?? "c333729b-d060-4b74-a49d-7686a8353481",
  secretKey: process.env.HESABE_SECRET_KEY ?? "PkW64zMe5NVdrlPVNnjo2Jy9nOb7v1Xg",
  ivKey: process.env.HESABE_IV_KEY ?? "5NVdrlPVNnjo2Jy9",
  environment: process.env.HESABE_ENVIRONMENT ?? "sandbox",
});

// Sent as both responseUrl and failureUrl, and set as `Config.returnURL` in the app.
// Nothing is ever fetched from it: the SDK stops the navigation before it loads.
const RETURN_URL = process.env.RETURN_URL ?? "https://example.com/hesabe/return";

// The server owns the price. The app sends what was ordered, never what it costs.
const PRICE_FILS = 250;
const kwd = (fils) => `${Math.floor(fils / 1000)}.${String(fils % 1000).padStart(3, "0")}`;

const routes = {
  // The app asks for a payment session.
  "POST /session": async ({ quantity }) => {
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 20) {
      throw new BadRequest("quantity must be a whole number from 1 to 20");
    }
    const reference = `DEMO-${Date.now()}`;
    const session = await hesabe.checkout.create({
      amount: kwd(quantity * PRICE_FILS),
      orderReferenceNumber: reference,
      // 0 leaves the method to the app: one session serves KNET, cards and Apple Pay.
      paymentType: 0,
      responseUrl: RETURN_URL,
      failureUrl: RETURN_URL,
    });
    // `data` is what the SDK takes. It opens this one payment and nothing else.
    return { data: session.data, token: session.token, reference };
  },

  // The app says a payment ended. The server asks Hesabe itself before it releases
  // anything: what the app reports travelled through the customer's device.
  "POST /confirm": async ({ token }) => {
    if (typeof token !== "string" || !/^[0-9A-Za-z]+$/.test(token)) {
      throw new BadRequest("token is required");
    }
    try {
      const transaction = await hesabe.transactions.retrieve(token);
      return {
        paid: isSuccessful(transaction),
        status: transaction.status,
        amount: transaction.amount,
        reference: transaction.reference_number,
      };
    } catch (error) {
      // A session nobody has paid has no transaction, and Hesabe says "not found".
      if (error instanceof HesabeError && /not found/i.test(error.message)) {
        return { paid: false, status: "NOT_FOUND" };
      }
      throw error;
    }
  },

  "GET /health": async () => ({ ok: true, environment: hesabe.environment }),
};

class BadRequest extends Error {}

createServer(async (req, res) => {
  const route = `${req.method} ${new URL(req.url, "http://localhost").pathname}`;
  const handler = routes[route];
  const send = (status, body) => {
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify(body));
  };
  if (!handler) return send(404, { error: `no route for ${route}` });

  try {
    send(200, await handler(req.method === "POST" ? await readJson(req) : {}));
  } catch (error) {
    if (error instanceof BadRequest) return send(400, { error: error.message });
    if (error instanceof HesabeError) {
      console.error(`[hesabe] ${error.name}: ${error.message}`);
      return send(502, { error: error.message });
    }
    console.error(error);
    send(500, { error: "internal error" });
  }
}).listen(PORT, () => {
  console.log(`Hesabe demo backend on http://localhost:${PORT} (${hesabe.environment})`);
});

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  try {
    return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
  } catch {
    throw new BadRequest("body is not valid JSON");
  }
}

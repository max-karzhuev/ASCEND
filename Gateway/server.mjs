import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { GatewayError, fail, text, exactKeys, validateConfig, validateQuestion, validateSession, validateGrade, sessionSchema, gradeSchema, testSchema, teachingInstruction, gradingInstruction } from './schema.mjs';
import { providersFromEnv, callProvider } from './providers.mjs';

export class Quota {
  constructor(directory, perMinute = 10, perDay = 100) {
    this.directory = directory; this.minuteLimit = perMinute; this.dayLimit = perDay;
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.file = path.join(directory, 'quota.json'); this.state = { day: '', used: 0, minute: 0, minuteUsed: 0 };
    if (fs.existsSync(this.file)) {
      this.state = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      if (typeof this.state.day !== 'string' || !Number.isInteger(this.state.used) || !Number.isInteger(this.state.minuteUsed) || !Number.isInteger(this.state.minute)) throw new Error('Invalid quota state; refusing to reset usage silently');
    }
  }
  consume(now = Date.now()) {
    const day = new Date(now).toISOString().slice(0,10), minute = Math.floor(now / 60000);
    if (this.state.day !== day) this.state = { day, used: 0, minute, minuteUsed: 0 };
    if (this.state.minute !== minute) { this.state.minute = minute; this.state.minuteUsed = 0; }
    if (this.state.used >= this.dayLimit || this.state.minuteUsed >= this.minuteLimit) throw new GatewayError(429, 'usage_limit', 'Your gateway usage limit has been reached');
    this.state.used++; this.state.minuteUsed++;
    const temporary = `${this.file}.tmp`; fs.writeFileSync(temporary, JSON.stringify(this.state), { mode: 0o600 }); fs.renameSync(temporary, this.file);
  }
}
function authenticate(req, token) {
  const supplied = req.headers.authorization;
  if (typeof supplied !== 'string' || supplied.length > 512 || !supplied.startsWith('Bearer ')) return false;
  const hash = s => crypto.createHash('sha256').update(s).digest();
  return crypto.timingSafeEqual(hash(supplied.slice(7)), hash(token));
}
async function readJSON(req) {
  const chunks = []; let size = 0;
  for await (const chunk of req) { size += chunk.length; if (size > 65536) throw new GatewayError(413, 'request_size', 'Request exceeds 64 KB'); chunks.push(chunk); }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { fail('Request must be valid JSON'); }
}
export function createGateway({token, providers, quota, transport, delay}) {
  if (typeof token !== 'string' || token.length < 32 || token.includes('REPLACE_')) throw new Error('Set a random ASCEND_AUTH_TOKEN of at least 32 characters');
  let busy = 0;
  // Responses are cached briefly in memory for safe request retries. No prompt/answer logging or disk caching.
  const cache = new Map();
  const inFlight = new Set();
  const server = http.createServer(async (req,res) => {
    const respond = (status, data) => {
      if (res.destroyed) return;
      res.writeHead(status, {'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'}); res.end(JSON.stringify(data));
    };
    let counted = false;
    let activeID;
    const abort = new AbortController(); req.on('aborted', () => abort.abort()); res.on('close', () => { if (!res.writableEnded) abort.abort(); });
    try {
      if (!authenticate(req,token)) throw new GatewayError(401,'authentication','A valid ASCEND gateway token is required');
      if (req.method === 'GET' && req.url === '/v1/config') return respond(200, {providers: Object.fromEntries(Object.entries(providers).map(([k,v]) => [k,v.models])), usage: { used: quota.state.used, limit: quota.dayLimit, day: quota.state.day }, providerTested: false});
      if (req.method !== 'POST' || !['/v1/session','/v1/grade','/v1/test'].includes(req.url)) throw new GatewayError(404,'not_found','Unknown endpoint');
      if (!req.headers['content-type']?.startsWith('application/json')) throw new GatewayError(415,'content_type','Use application/json');
      const body = await readJSON(req);
      exactKeys(body, ['requestID','provider','model', ...(req.url === '/v1/session' ? ['config'] : req.url === '/v1/grade' ? ['question','answer','hintsUsed','mode'] : [])]);
      text(body.requestID,100,'request ID'); text(body.model,100,'model'); text(body.provider,30,'provider');
      const config = providers[body.provider];
      if (!config || !config.models.includes(body.model)) throw new GatewayError(503,'unconfigured','This provider/model is not configured on the gateway');
      let input, schema, system, validate;
      if (req.url === '/v1/session') {
        input = validateConfig(body.config); schema = sessionSchema; system = teachingInstruction;
        validate = value => validateSession(value, body.config.count);
      } else if (req.url === '/v1/grade') {
        validateQuestion(body.question); text(body.answer,12000,'answer');
        if (!Number.isInteger(body.hintsUsed) || body.hintsUsed < 0 || body.hintsUsed > 3 || !['practice','assessment'].includes(body.mode)) fail('Invalid attempt settings');
        input = { question: body.question, answer: body.answer, hintsUsed: body.hintsUsed, mode: body.mode };
        schema = gradeSchema; system = gradingInstruction; validate = validateGrade;
      } else {
        input = {request:'Return ok true to confirm structured generation works.'}; schema = testSchema; system = 'Return only the requested JSON object.';
        validate = value => { exactKeys(value,['ok']); if (value.ok !== true) fail('Invalid connection test'); return value; };
      }
      const hash = crypto.createHash('sha256').update(req.url + JSON.stringify(body)).digest('hex');
      for (const [key,value] of cache) if (value.expires < Date.now()) cache.delete(key);
      const previous = cache.get(body.requestID);
      if (previous) {
        if (previous.hash !== hash) throw new GatewayError(409,'request_conflict','A request ID was reused with different input');
        return respond(200,previous.result);
      }
      if (inFlight.has(body.requestID)) throw new GatewayError(409,'request_pending','This request is already running');
      if (busy >= 2) throw new GatewayError(429,'concurrency','Two provider requests are already running');
      quota.consume(); busy++; counted = true; activeID = body.requestID; inFlight.add(activeID);
      const result = await callProvider({provider:body.provider,config,model:body.model,system,input,schema,signal:abort.signal,transport,delay});
      try { validate(result); } catch { throw new GatewayError(502,'invalid_provider_response','The provider returned a response that failed validation. Nothing was graded.'); }
      if (cache.size >= 100) cache.delete(cache.keys().next().value);
      cache.set(body.requestID,{hash,result,expires:Date.now()+5*60*1000});
      respond(200,result);
    } catch (error) {
      const known = error instanceof GatewayError;
      respond(known ? error.status : 500, {error: {code: known ? error.code : 'internal', message: known ? error.message : 'The gateway could not complete this request'}});
    } finally { if (counted) busy--; if (activeID) inFlight.delete(activeID); }
  });
  server.requestTimeout = 45000; server.headersTimeout = 10000; server.keepAliveTimeout = 5000;
  return server;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const env = process.env;
  const bounded = (key,fallback,max) => { const n = Number(env[key] || fallback); if (!Number.isInteger(n) || n < 1 || n > max) throw new Error(`Invalid ${key}`); return n; };
  const quota = new Quota(env.STATE_DIR || '.gateway-state', bounded('REQUESTS_PER_MINUTE',10,100), bounded('REQUESTS_PER_DAY',100,10000));
  const server = createGateway({token:env.ASCEND_AUTH_TOKEN,providers:providersFromEnv(env),quota});
  const port = bounded('PORT',8787,65535), host = env.HOST || '127.0.0.1';
  server.listen(port,host, () => process.stdout.write(`ASCEND gateway listening on ${host}:${port}; request content logging disabled.\n`));
}

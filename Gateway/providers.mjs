import https from 'node:https';
import dns from 'node:dns/promises';
import net from 'node:net';
import { GatewayError } from './schema.mjs';

// Fail closed for private, loopback, link-local, multicast, documentation and transition ranges.
export function publicIP(address) {
  const family = net.isIP(address);
  if (family === 4) {
    const [a,b,c] = address.split('.').map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 || (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && (b === 168 || b === 0 || (b === 88 && c === 99))) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) || (a === 203 && b === 0 && c === 113));
  }
  if (family === 6) {
    const first = parseInt(address.split(':')[0], 16);
    return first >= 0x2000 && first <= 0x3fff && !address.toLowerCase().startsWith('2001:') && !address.toLowerCase().startsWith('2002:');
  }
  return false;
}
export function validateEndpoint(raw, allowedHosts) {
  let url; try { url = new URL(raw); } catch { throw new GatewayError(503, 'configuration', 'Invalid compatible endpoint configuration'); }
  if (url.protocol !== 'https:' || (url.port && url.port !== '443') || url.username || url.password || url.search || url.hash ||
      net.isIP(url.hostname.replaceAll(/[\[\]]/g, '')) || !allowedHosts.includes(url.hostname.toLowerCase()) || url.pathname.includes('..')) {
    throw new GatewayError(503, 'configuration', 'Compatible endpoint must be an allowlisted public HTTPS hostname on port 443');
  }
  return url;
}
export async function secureTransport(url, headers, body, signal, resolver = dns.lookup) {
  signal.throwIfAborted();
  const addresses = await new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener('abort', abort, {once:true});
    Promise.resolve(resolver(url.hostname, {all:true})).then(
      value => { signal.removeEventListener('abort', abort); resolve(value); },
      error => { signal.removeEventListener('abort', abort); reject(error); }
    );
  });
  signal.throwIfAborted();
  if (!addresses.length || addresses.some(({address}) => !publicIP(address))) throw new GatewayError(503, 'blocked_endpoint', 'Upstream resolves to a prohibited address');
  const pinned = addresses[0];
  return await new Promise((resolve, reject) => {
    const req = https.request(url, {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) },
      signal, servername: url.hostname,
      lookup: (_hostname, options, callback) => {
        if (options?.all) callback(null, [pinned]); else callback(null, pinned.address, pinned.family);
      }
    }, res => {
      const chunks = []; let bytes = 0;
      res.on('data', chunk => { bytes += chunk.length; if (bytes > 262144) { req.destroy(new GatewayError(502, 'provider_response', 'Provider response exceeded the size limit')); } else chunks.push(chunk); });
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
      res.on('error', reject);
    });
    req.on('error', reject); req.end(body);
  });
}
export function providersFromEnv(env) {
  const list = name => (env[name] || '').split(',').map(s => s.trim()).filter(Boolean);
  const result = {};
  for (const [id,prefix] of [['openai','OPENAI'],['anthropic','ANTHROPIC'],['gemini','GEMINI'],['compatible','COMPATIBLE']]) {
    const key = env[`${prefix}_API_KEY`], models = list(`${prefix}_MODELS`).filter(m => /^[a-zA-Z0-9_.-]{1,100}$/.test(m) && !m.startsWith('YOUR_'));
    if (key && models.length) result[id] = { key, models };
  }
  if (result.anthropic) result.anthropic.version = env.ANTHROPIC_VERSION || '2023-06-01';
  if (result.compatible) result.compatible.base = validateEndpoint(env.COMPATIBLE_BASE_URL, list('COMPATIBLE_ALLOWED_HOSTS')).href.replace(/\/$/, '');
  return result;
}
export function adapterRequest(provider, config, model, system, input, schema) {
  const user = JSON.stringify(input);
  if (provider === 'openai') return {
    url: new URL('https://api.openai.com/v1/responses'), headers: { authorization: `Bearer ${config.key}` },
    body: { model, store: false, instructions: system, input: user, max_output_tokens: 6000, text: { format: { type: 'json_schema', name: 'ascend_result', strict: true, schema } } },
    extract: r => { if (r.status !== 'completed') throw new Error('Incomplete response'); return r.output?.flatMap(o => o.content || []).filter(c => c.type === 'output_text').map(c => c.text).join(''); }
  };
  if (provider === 'anthropic') return {
    url: new URL('https://api.anthropic.com/v1/messages'), headers: { 'x-api-key': config.key, 'anthropic-version': config.version },
    body: { model, system, max_tokens: 6000, messages: [{ role: 'user', content: user }], output_config: { format: { type: 'json_schema', schema } } },
    extract: r => { if (r.stop_reason !== 'end_turn') throw new Error('Incomplete response'); return r.content?.filter(c => c.type === 'text').map(c => c.text).join(''); }
  };
  if (provider === 'gemini') return {
    url: new URL(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`), headers: { 'x-goog-api-key': config.key },
    body: { systemInstruction: { parts: [{ text: system }] }, contents: [{ role: 'user', parts: [{ text: user }] }], generationConfig: { maxOutputTokens: 6000, responseMimeType: 'application/json', responseJsonSchema: schema } },
    extract: r => { const c = r.candidates?.[0]; if (c?.finishReason !== 'STOP') throw new Error('Incomplete response'); return c.content?.parts?.filter(p => p.text && !p.thought).map(p => p.text).join(''); }
  };
  if (provider === 'compatible') return {
    url: new URL(`${config.base}/chat/completions`), headers: { authorization: `Bearer ${config.key}` },
    body: { model, max_tokens: 6000, messages: [{ role: 'system', content: system }, { role: 'user', content: user }], response_format: { type: 'json_schema', json_schema: { name: 'ascend_result', strict: true, schema } } },
    extract: r => { if (r.choices?.[0]?.finish_reason !== 'stop') throw new Error('Incomplete response'); return r.choices[0].message?.content; }
  };
  throw new GatewayError(400, 'provider', 'Unsupported provider');
}
export async function callProvider({provider,config,model,system,input,schema,signal,transport = secureTransport,delay = ms => new Promise(r => setTimeout(r, ms))}) {
  const request = adapterRequest(provider,config,model,system,input,schema);
  const combined = AbortSignal.any([signal || new AbortController().signal, AbortSignal.timeout(35000)]);
  for (let attempt = 0; attempt < 2; attempt++) {
    let response;
    try { response = await transport(request.url, request.headers, JSON.stringify(request.body), combined); }
    catch (error) {
      if (error instanceof GatewayError) throw error;
      if (combined.aborted) throw new GatewayError(504, 'timeout', 'Provider request timed out or was cancelled. No feedback was saved.');
      throw new GatewayError(502, 'provider_unavailable', 'Could not reach the AI provider');
    }
    if ((response.status === 429 || response.status === 503) && attempt === 0) {
      await delay(700);
      if (combined.aborted) throw new GatewayError(504, 'timeout', 'Provider request timed out or was cancelled. No feedback was saved.');
      continue;
    }
    if (response.status === 401 || response.status === 403) throw new GatewayError(502, 'provider_authentication', 'The server’s provider credentials were rejected');
    if (response.status === 429) throw new GatewayError(429, 'provider_rate_limit', 'Provider rate limit reached. Try again later.');
    if (response.status < 200 || response.status >= 300) throw new GatewayError(502, 'provider_error', `Provider rejected the request (HTTP ${response.status}). Check model access and structured-output support.`);
    try {
      const parsed = JSON.parse(response.body); const text = request.extract(parsed);
      if (typeof text !== 'string' || text.length > 200000) throw new Error('Missing output');
      return JSON.parse(text);
    } catch { throw new GatewayError(502, 'invalid_provider_response', 'The provider returned incomplete or invalid structured data. Try a smaller session.'); }
  }
}

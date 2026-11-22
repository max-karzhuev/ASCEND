# ASCEND private AI gateway

A dependency-free Node service for one person’s Mac and iPhone. It requires a strong bearer token on **every** endpoint. Provider API keys remain on the server. No infrastructure has been deployed and no live provider request was made during delivery.

## Local development

Use Node 22 or newer. From this directory:

```sh
cp .env.example .env
chmod 600 .env
node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"
```

Copy the generated value into `ASCEND_AUTH_TOKEN` in `.env`; store it securely. Enter that same gateway token into the app, not an upstream API key. The server refuses the placeholder token.

Set at least one provider’s key and a comma-separated allowlist of **exact model IDs your API account can use**:

```dotenv
OPENAI_API_KEY=your-server-side-key
OPENAI_MODELS=your-enabled-structured-output-model
```

The example values above are placeholders, not credentials or model recommendations. Models are deliberately not hardcoded to an unverified “latest” name. Equivalent pairs are `ANTHROPIC_API_KEY` / `ANTHROPIC_MODELS`, `GEMINI_API_KEY` / `GEMINI_MODELS`, and `COMPATIBLE_API_KEY` / `COMPATIBLE_MODELS`.

```sh
npm test
npm start
```

The default listener is `127.0.0.1:8787`. In a **Debug** ASCEND build, use `http://localhost:8787`. Release builds require HTTPS. An iPhone simulator on the same Mac can use localhost. A physical iPhone needs a reachable HTTPS gateway; its localhost is the phone itself.

In ASCEND Settings, save the URL, save the gateway token to Keychain, choose a provider, select **Load gateway models**, choose a model, and select **Test provider**. Loading models only proves authenticated gateway reachability. Testing performs a small real generation and can incur provider API charges. Consumer chatbot subscriptions do not automatically establish API access.

## HTTP contract

All requests require `Authorization: Bearer <gateway token>`. POST requests require JSON. There is no unauthenticated health/proxy route and no browser CORS allowance.

| Endpoint | Behavior |
| --- | --- |
| `GET /v1/config` | Returns enabled providers/model allowlists and the personal usage counter; no credentials. Does not claim the provider is connected. |
| `POST /v1/test` | Accepts requestID, provider, model; runs a minimal structured-output test. |
| `POST /v1/session` | Adds config: subject, subtopic, ability, difficulty, count 1–10, practice/assessment mode. Returns validated questions. |
| `POST /v1/grade` | Adds one question/reference, answer, hintsUsed, and mode. Returns correct, constructive feedback, and reviewTopic. |

App requests cannot supply an arbitrary upstream URL, authentication header, system instruction, or model outside the administrator’s allowlist. Unknown fields are rejected. Grading never executes programming answers.

## Adapter differences

- OpenAI: `/v1/responses`, `instructions` + `input`, `text.format` JSON schema, `store: false`; checks completed status and output text.
- Anthropic: `/v1/messages`, `x-api-key`, `anthropic-version`, `system` + messages, `output_config.format`; checks `end_turn` and text blocks. `ANTHROPIC_VERSION` is configurable; the default compatibility version is `2023-06-01`.
- Gemini: `/v1beta/models/{model}:generateContent`, `x-goog-api-key`, `systemInstruction`, `contents`, `generationConfig.responseMimeType` and `responseJsonSchema`; checks the candidate finish reason.
- Compatible: configured server-side base URL plus `/chat/completions`, bearer auth, messages, strict JSON-schema `response_format`. Use only an endpoint/model that actually implements this contract.

Malformed/refused/truncated responses fail explicitly. Deterministic multiple-choice/numerical grading occurs on-device from the cached answer key. AI feedback remains fallible and is labeled accordingly.

## Limits and network restrictions

- 64 KB incoming request limit; 256 KB upstream response limit; structured-result and field bounds; 6,000 output tokens maximum.
- A 35-second total provider deadline. One retry only for HTTP 429/503, after 700 ms. Authentication failures and uncertain network failures are not retried automatically.
- Two in-flight provider calls maximum. Duplicate running request IDs are rejected. Identical completed requests are cached in memory for five minutes to avoid repeated generation on retry; changed input using the same ID returns a conflict.
- Default 10 requests/minute and 100/day across both devices. Counters persist in `STATE_DIR/quota.json`; failures also consume a request. These are request budgets, not currency guarantees. Configure provider-side spending limits too.
- No logging of prompts, answers, provider responses, or credentials. Only the listening address is logged at startup. The ephemeral response cache is memory-only.
- Custom endpoints require an exact hostname allowlist, HTTPS, port 443, no embedded credentials/query/fragment, and a server-configured path. IP literals are rejected. DNS answers are checked for prohibited ranges, including loopback/private/link-local/metadata destinations; the checked address is pinned for the TLS request. Redirects are not followed. The conservative IPv6 policy intentionally rejects several transition/special-purpose ranges.

For a custom service, set both:

```dotenv
COMPATIBLE_BASE_URL=https://api.your-service.example/v1
COMPATIBLE_ALLOWED_HOSTS=api.your-service.example
```

Use a real public hostname in your deployment. A localhost/internal upstream is intentionally not supported. Do not broaden the allowlist to user-provided hosts.

## Deploy on infrastructure you control

This is a single-instance personal gateway. Do not horizontally replicate it with independent quota files or expose it as a public multi-tenant proxy. Use an existing host, or obtain explicit authorization before purchasing infrastructure.

1. Provision a supported Node runtime, or build the supplied Dockerfile.
2. Inject the production environment from a secret manager or a protected `.env` file; never copy it into the image or app bundle.
3. Persist `STATE_DIR` on a private writable volume. The Docker image runs as the non-root `node` user, so the volume must be writable by that user.
4. Bind the service to loopback/private networking behind an HTTPS reverse proxy. Do not log Authorization headers or request/response bodies at the proxy.
5. Set DNS and TLS for your gateway hostname. Point the app at that HTTPS origin. The app does not follow redirects with its authentication token.
6. Keep the process supervised by your host’s service manager. Restarting the service restores its quota counters; intentionally changing/discarding the volume resets those counters.
7. Test authentication, rate limiting, and a real provider connection using your own account. Live availability and model support are not established by the fixture tests.

Example Docker commands, to run only on your chosen infrastructure:

```sh
docker build -t ascend-gateway .
docker volume create ascend-gateway-state
docker run -d --name ascend-gateway --restart unless-stopped \
  --env-file .env --read-only --tmpfs /tmp --cap-drop ALL \
  --security-opt no-new-privileges \
  -p 127.0.0.1:8787:8787 -v ascend-gateway-state:/data ascend-gateway
```

The `.env` example’s `HOST=127.0.0.1` would override the Docker image’s listener. For a container deployment set `HOST=0.0.0.0` and `STATE_DIR=/data` in the deployment environment; the host-side published port above remains loopback-only.

Example reverse-proxy route with Caddy (replace the hostname):

```caddyfile
ai.your-domain.example {
    reverse_proxy 127.0.0.1:8787
}
```

No deployment command above was executed during this task. Docker deployment itself remains an external setup/validation step.

## Token rotation and troubleshooting

Rotate `ASCEND_AUTH_TOKEN` on the server, restart it, and replace the saved token on each device. Tokens are scoped in Keychain to the exact entered gateway URL; changing the URL requires saving the token for that URL again.

- **401 authentication:** the gateway token is missing or incorrect.
- **503 unconfigured:** that provider/model is absent from the server’s enabled allowlist.
- **502 provider_authentication:** the upstream key/account was rejected; inspect server environment without exposing it in logs.
- **429 usage_limit/provider_rate_limit:** a local gateway budget or upstream limit was reached.
- **502 invalid_provider_response:** incomplete/refused output or schema validation failure; reduce session size or choose a supported model.
- **504 timeout:** the answer stays saved on-device awaiting feedback; retry later.
- **blocked_endpoint:** DNS or URL validation rejected the upstream destination. Fix the public server configuration; do not remove the protection.

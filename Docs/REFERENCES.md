# Official implementation references

Checked during implementation on 21 November 2026. Adapters are fixture-tested; this does not establish live account/model availability.

- [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs): Responses API `text.format` with strict JSON schema; handle incomplete output and refusals explicitly.
- [OpenAI Responses creation](https://developers.openai.com/api/reference/resources/responses/methods/create): request/response shape and output limits.
- [Anthropic structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs): Messages API `output_config.format`, separate system prompt, and text content blocks.
- [Anthropic Messages](https://platform.claude.com/docs/en/api/messages): provider-specific Messages request and response contract. The API version header is server-configurable; the compatibility default is `2023-06-01`.
- [Gemini structured outputs](https://aistudio.google.com/docs/structured-output) and [generateContent reference](https://aistudio.google.com/api-reference/generate-content): `contents`, `systemInstruction`, `generationConfig`, and candidate completion checks.
- [Apple CloudKit zone changes](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation): custom-zone change cursors and explicit record exchange.
- [Apple CloudKit schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema): separate development/production schemas and deployment.
- [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device): physical-device setup for Xcode-installed apps.

OpenAI-compatible services are not assumed to support every OpenAI feature. The compatible adapter uses Chat Completions with a JSON-schema response format. The administrator must choose a model/endpoint that supports that contract; failures are surfaced rather than silently falling back to fabricated data.

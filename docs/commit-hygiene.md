# Commit and leak hygiene

Camera credentials, approval identities, signing material and private
operator data stay outside source control. Use the ignored `captures/` and
`.local/` directories for raw captures, lab identities and local setup.

Never commit Wi-Fi passwords, identity exports, packet captures, footage,
keystores, service-account JSON, OAuth tokens, Sentry upload tokens or filled
local configuration files. Files such as `*.local.xcconfig`,
`*.local.properties`, `.env`, `*.jks` and `*.keystore` are ignored. Example
files use placeholders. Review staged paths as well as content.

Before sharing a change, run the existing metadata checks and scan history:

```sh
just check
git diff --check
git diff --cached --check
gitleaks git --redact --no-banner --log-opts=--all
```

Gitleaks is a separate local tool; hosted CI also runs its pinned scanner.
Do not add broad test or source allowlists to hide a finding. A scanner does
not identify every private name, device identifier, screenshot or camera
serial, so review those manually before sharing diagnostics or research.

A later deletion does not remove data from Git history, forks or clones. If
a credential was committed, stop sharing it, rotate it and contact the
maintainer privately using [`../SECURITY.md`](../SECURITY.md). Do not rewrite
shared history as a routine cleanup step.

Preserve vendor licenses, exact golden fixtures and the provider attribution
for camera LUTs. A bundled third-party file does not become Apache-licensed
because the app uses Apache 2.0. Current camera LUT provenance is documented
in [`../Resources/CameraLUTs/README.md`](../Resources/CameraLUTs/README.md).

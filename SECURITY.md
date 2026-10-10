# Security Policy

OpenInstaCine connects to the Insta360 Luna Ultra over Bluetooth and the
camera's local Wi-Fi network. Approval identities, Wi-Fi passphrases, raw
captures, optional Frame.io credentials and signing material are secrets.

## Supported versions

The project is pre-release; only the latest `main` is supported.

## Reporting a vulnerability

Do not open a public issue for security vulnerabilities. Report privately via
[GitHub Security Advisories](https://github.com/erik-sutton95/OpenInstaCine/security/advisories/new).
Include reproduction steps, affected versions and impact. Remove camera Wi-Fi
passwords, approval identities, operator details and footage from attachments.

We aim to acknowledge reports within 7 days and keep you updated while we
investigate. We appreciate coordinated disclosure and credit reporters who
wish to be named.

## Trust boundaries and diagnostics

Bluetooth pairing, camera Wi-Fi, local media storage and optional cloud
services are separate trust boundaries. The app stores camera approval and
Wi-Fi credentials through its configured platform credential stores; they
must not enter saved-camera JSON, source control or public reports.

Configured builds offer opt-in Sentry reliability reporting. Automatic
reports exclude images and use the existing privacy redaction. Explicit
support reports can include details or screenshots chosen by the operator.
See the [privacy policy](https://opencapture.org/openinstacine/privacy/) for
the reporting controls and current data handling. Do not include credentials,
raw camera packets or footage in diagnostic events.

Raw captures and lab identities belong in the ignored `captures/` and
`.local/` directories. Commit and leak hygiene is documented in
[`docs/commit-hygiene.md`](docs/commit-hygiene.md).

# OpenInstaCine handbook

Astro [Starlight](https://starlight.astro.build/) site for OpenInstaCine: Luna
Ultra protocol, iOS and Android apps, and how to build. Markdown in
`src/content/docs/` is the public source. Research logs and status ledgers stay
in `docs/` and are summarized here, not copied.

When protocol, app UX, or setup changes, update the matching page in the same
change. Standard: `src/content/docs/contribute/documentation.md`.

Published at [opencapture.org/openinstacine/docs](https://opencapture.org/openinstacine/docs/).

## Local preview

```bash
cd handbook
npm ci
npm run dev
```

Then open [http://localhost:4321/](http://localhost:4321/). Local preview is the
site root; the published build uses the base path:

```bash
HANDBOOK_BASE=/openinstacine/docs npm run build   # output in handbook/dist/
```

## Dependency maintenance

Commit `package.json` and `package-lock.json` together. After a dependency update,
run `npm ci`, `npm audit` and the production-base build above. These dependencies
build the static handbook; build-time parsing and image vulnerabilities still
matter even when the deployed output has no Node server.

The scoped `postcss-nested` override selects `postcss-selector-parser` 7.1.6 to
address [GHSA-rj75-hqrm-r3gf](https://github.com/postcss/postcss-selector-parser/security/advisories/GHSA-rj75-hqrm-r3gf).
It preserves the existing Astro and Starlight versions. Validate the full build
when changing it, and remove the override when the parent supports a patched
parser directly.

The lock also selects `http-cache-semantics` 4.3.0, outside the current affected
range of [GHSA-ch52-4w7c-c8xp](https://github.com/advisories/GHSA-ch52-4w7c-c8xp).
A clean audit does not demonstrate a repair of the advisory's disputed revalidation
behavior. This handbook's Astro use is build-time remote-image cache expiry,
not an authenticated shared response cache. Keep the advisory distinction when
reviewing future dependency or deployment changes.

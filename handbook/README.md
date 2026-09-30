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

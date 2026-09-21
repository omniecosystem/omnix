# Omnix website

Developer portal for the Omnix on-device intelligence engine.

## Development

```shell
pnpm install
pnpm dev
```

## Validation

```shell
pnpm lint
pnpm typecheck
pnpm build
```

The production build is a static export in `out/` and can be deployed to a
static host such as Cloudflare Pages.

## Cloudflare Pages

Connect the **Omnix repository** to a Cloudflare Pages project. The website can
remain a subdirectory; configure the Pages build as follows:

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Root directory | `website` |
| Framework preset | Next.js (Static HTML Export) |
| Build command | `pnpm build` |
| Build output directory | `out` |

No runtime environment variables or Pages Functions are required. To prevent
engine-only commits from rebuilding the site, set the build-watch include path
to `website/*`.

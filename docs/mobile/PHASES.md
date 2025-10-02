# Flixor Mobile — Delivery Plan (Phases & Milestones)

This document is the single source of truth for the mobile (iOS/Android) implementation. It defines phases, scope, deliverables, acceptance criteria, risks, and references to code/endpoints.

Status key: [P] Planned, [WIP] In Progress, [D] Done


## Phase 0 — Bootstrap & Environment [D]
- Goal: Create an Expo + React Native app scaffold aligned to a stable SDK; foundation for future phases.
- Scope:
  - Expo SDK pinned (54), RN/React compatible
  - TS config, navigation, basic folder structure
  - Yarn/npm install guidance and doctor scripts
- Deliverables:
  - `apps/mobile` project; entry, navigation, TS config
  - Minimal Home screen placeholder
- Acceptance criteria:
  - App boots on iOS/Android; hot reload works
  - Dependency doctor passes (or issues documented with workaround)
- References: `apps/mobile/*`


## Phase 1 — Onboarding (Server URL) [D]
- Goal: User can enter/test backend URL and persist it securely.
- Scope:
  - Onboarding screen with URL input and `/health` test
  - Persist base URL; handle clear/replace
- Deliverables:
  - Screen: `Onboarding.tsx`
  - API: `MobileApi.health()` + storage helpers
- Acceptance criteria:
  - URL is validated; health status & latency logged
  - On success, app navigates to next step (Login)
- References: `apps/mobile/src/screens/Onboarding.tsx`, `apps/mobile/src/api/client.ts`


## Phase 2 — Authentication (Plex PIN + JWT) [WIP]
- Goal: Sign in with Plex via PIN; store JWT; session restore.
- Scope:
  - Start PIN; open Plex auth (in-app session)
  - Poll/recheck; on success receive JWT (mobile=1)
  - Save token; add Authorization: Bearer
  - Foreground re-check + manual re-check button
- Deliverables:
  - Screen: `Login.tsx`
  - API: `createPin`, `checkPin`, `session` with logs
  - Backend: `GET /api/auth/plex/pin/:id?mobile=1` returns `{ token }`
- Acceptance criteria:
  - After browser auth, app navigates to Home with token saved
  - Logs show calls and HTTP statuses
- Backend references:
  - `backend/src/api/auth.ts` (mobile token branch)
  - `backend/src/middleware/auth.ts` (Bearer auth)


## Phase 3 — Home (Foundations) [P]
- Goal: Render real content tiles via backend (Continue Watching, Trending, etc.).
- Scope:
  - Fetch session; show greeting/avatar
  - Render basic rows using FlatList (placeholder visuals ok)
- Deliverables:
  - Screen: `Home.tsx` fleshed out with rows
  - API: calls to `/api/trakt/*`, `/api/plex/*`
- Acceptance criteria:
  - Scrolling lists load without frame drops
  - Errors display friendly messages + retry


## Phase 4 — Details & Episodes [P]
- Goal: Show details view (hero art, ratings, seasons/episodes with progress).
- Scope:
  - Item details + IMDb/RT badges
  - Episodes list with progress bars; Continue/Play
- Deliverables:
  - Screen: `Details.tsx`
  - API: `/api/plex/metadata`, `/api/plex/ratings/*`, `/api/tmdb/*`
- Acceptance criteria:
  - Episode progress updated on return from player
  - Continue/Play picks correct resume episode


## Phase 5 — Player v1 (HLS, Resume, Controls) [P]
- Goal: Solid HLS playback on iOS/Android.
- Scope:
  - Use `react-native-video` (AVPlayer/ExoPlayer)
  - Request HLS stream; ABR; basic track selection
  - Resume progress updates to `/api/plex/progress`
- Deliverables:
  - Screen: `Player.tsx`
  - Backend: Ensure `protocol=hls` path + `.m3u8` decision (add if missing)
- Acceptance criteria:
  - Start/seek/pause; time remaining; no looping at credits
  - Resume position persists and re-applies once
- Backend references:
  - `backend/src/api/plex.ts` stream endpoint
  - `backend/src/services/plex/PlexClient.ts` decision/URL builders


## Phase 6 — Player v2 (Skip Credits, Next Episode) [P]
- Goal: Netflix-like credits detection and next episode flow.
- Scope:
  - Fetch markers; show Skip Credits CTA near end
  - Next episode countdown overlay + auto-next
  - Back button returns to series details
- Deliverables:
  - Player overlay components
  - API: `metadata?includeMarkers=1`
- Acceptance criteria:
  - Movies exit to details at credits or last-30s fallback
  - Episodes auto-next with visible countdown and cancel


## Phase 7 — Library & Search [P]
- Goal: Large grids, filters, and search with great performance.
- Scope:
  - FlashList-based grids; server section switcher
  - Filters (type/genre/year/resolution); debounced search
- Deliverables:
  - Screens: `Library.tsx`, `Search.tsx`
  - API: `/api/plex/library/*`, `/api/plex/search`
- Acceptance criteria:
  - No jank on large libraries; images load progressively


## Phase 8 — Settings & Server Selection [P]
- Goal: Control server and endpoints; view connection health.
- Scope:
  - Show server list; set current; select preferred URI
  - Health check + latency; change backend base URL
- Deliverables:
  - Screen: `Settings.tsx`
  - API: `/api/plex/servers`, `/connections`, `/endpoint`, `/servers/current`
- Acceptance criteria:
  - Switching servers/URIs works without app restart


## Phase 9 — Performance, Images & Caching [P]
- Goal: Make the app feel snappy and efficient.
- Scope:
  - Use `/api/image/proxy` (w/q/f) with FastImage
  - Prefetch on focus; LQIP placeholders; memory budgets
- Deliverables:
  - Image utilities + cache policies
- Acceptance criteria:
  - Smooth scroll; no crashes due to memory spikes


## Phase 10 — QA, Telemetry (Opt‑out), Release [P]
- Goal: Ship to TestFlight/Play Internal; reliable and observable.
- Scope:
  - Crashlytics/Sentry (opt‑out flag), basic event logs
  - EAS build workflows; test checklists; store metadata
- Deliverables:
  - EAS configs; App Store Connect/Play Console setup docs
- Acceptance criteria:
  - Builds install; basic smoke passes on real devices


## Cross-Cutting Concerns
- Security:
  - JWT in secure storage (Keychain/Keystore or Expo SecureStore)
  - HTTPS preferred; ATS exceptions only for dev
- Error handling:
  - Centralized toasts/modals; retries & backoff
- Logging:
  - Verbose logs during dev (toggleable), minimal in prod
- Accessibility:
  - Focus order, readable sizes, color contrast


## Risks & Mitigations
- RN player parity (tracks/subtitles):
  - Mitigate by surfacing backend track info and best-effort pickers
- LAN variability:
  - Keep server selection fast with health checks; fallbacks
- Dependency drift:
  - Pin Expo/RN; avoid auto-fix until planned migrations


## Definition of Done (per Phase)
- Code compiles for iOS/Android
- Happy-path manual test passed on both platforms
- Logs quiet (warnings triaged)
- README/inline usage doc updated


## Implementation Traceability
- Mobile app: `apps/mobile/*`
- Backend auth (mobile): `backend/src/api/auth.ts`, `backend/src/middleware/auth.ts`
- Plex APIs: `backend/src/api/plex.ts`, `backend/src/services/plex/PlexClient.ts`
- Image proxy: `backend/src/api/image-proxy.ts`


## Backlog (Nice-to-haves)
- QR Connect flow from web
- Deep-link return with explicit scheme handling
- Top shelf / widgets (future)

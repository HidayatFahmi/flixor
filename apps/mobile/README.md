Flixor Mobile (React Native)

Overview
- React Native app for iOS/Android that connects to your Flixor backend and Plex.
- First‑run onboarding asks for your backend URL (e.g., http://192.168.1.10:3001).
- Login uses Plex PIN flow and receives a mobile token (JWT) from the backend.

Dependencies (pinned to Expo SDK 54)
- expo ~54.0.0
- react 19.1.0, react-native 0.81.4
- expo-linking ~8.0.8, expo-status-bar ~3.0.8
- @react-native-async-storage/async-storage 2.2.0
- @shopify/flash-list 2.0.2

Run
1) Backend must be running and reachable on your LAN.
2) From apps/mobile:
   - yarn install (recommended) or npm install (may need --legacy-peer-deps)
   - npx expo doctor --fix-dependencies (optional)
   - npx expo start -c
3) Launch on simulator/device (i/a or scan QR).
4) Enter backend URL → Test & Continue → Continue with Plex → complete in browser.

Notes
- If npm tries to pull mismatched versions, use yarn or npm with --legacy-peer-deps.
- iOS cleartext HTTP needs ATS exceptions in prebuilt apps; HTTPS recommended.

Implementation plan
- See the detailed phase breakdown in `docs/mobile/PHASES.md` for milestones, scope, deliverables, and acceptance criteria. Treat it as the reference for development and reviews.

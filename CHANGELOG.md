# Changelog

## [Unreleased]

### Fixed (2026-10-26, rate-limit-recovery) [0.5h]
- The widget could sit on "Rate limited. Backing off." for days with week-old numbers. It now checks the sign-in's expiry before calling the API (an expired token shows the sign-in-expired state instead of a misleading 429), honours `Retry-After`, and no longer polls early when the popover is opened during a backoff.
- Stale numbers no longer pose as live: a window that reset since the last fetch says "reset" instead of "1m", and "Updated" rolls over to days ("6d", not "166h"). Error banners now carry the HTTP status.

### Added (2026-10-16, open-source-release) [0.25h]
- Prepared the repo for public release: MIT license, an unofficial-project note, a screenshots section (menu bar strip plus the four popover states, rendered from sample data), an https clone URL, first-launch keychain guidance and a plain statement of what happens to your sign-in.
- Audited the code and full git history for secrets with gitleaks (no findings) before making it public.

### Added (2026-10-16, claude-usage-bar-v2) [0.27h]
- Rebuilt the menu bar usage widget as a versioned repo.
- **New visuals:**
  - an animated pixel mascot whose mood follows session usage
  - drifting pixel clouds
  - hearts for weekly headroom
  - a big colored percentage
  - glowing progress bars
  - a "resets in" countdown
- Reads `limits[]` from the OAuth usage endpoint (session, weekly all-models, model-scoped weekly). If that is missing, it falls back to the older `five_hour` / `seven_day` fields.
- Added `--check` (one live fetch, for diagnosis) and `--snapshot` (fixture renders plus animation frames, for design review).

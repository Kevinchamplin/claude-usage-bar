# Changelog

## [Unreleased]

### Added (2026-10-16, claude-usage-bar-v2) [1.5h]
- Rebuilt the menu bar usage widget as a versioned repo. The v1 source lived only on the MacBook.
- **New visuals:**
  - an animated pixel mascot whose mood follows session usage
  - drifting pixel clouds
  - hearts for weekly headroom
  - a big colored percentage
  - glowing progress bars
  - a "resets in" countdown
- Reads `limits[]` from the OAuth usage endpoint (session, weekly all-models, model-scoped weekly). If that is missing, it falls back to the older `five_hour` / `seven_day` fields.
- Added `--check` (one live fetch, for diagnosis) and `--snapshot` (fixture renders plus animation frames, for design review).

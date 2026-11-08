# Windows YouTube TV / Premium compatibility test

This feature branch is experimental and must not be merged into main until its Windows build and account behavior are verified.

## Non-negotiable rules
- YouTube video playback and browsing should remain inside MegaWatch.
- Do not collect Google passwords, cookies, refresh tokens from unrelated applications, or device identity secrets.
- Do not spoof certified Android TV device identities, circumvent ads, or promise Premium benefits for a third-party player.
- Do not modify unrelated MegaWatch / Claude work.
- An OAuth login is not evidence that Premium playback is enabled.

## Windows verification checklist
1. GitHub Actions produces a portable Windows build artifact and the app starts.
2. Search inside MegaWatch returns actual videos and handles empty/error results.
3. Controller D-pad, select, back and fullscreen video controls work.
4. Replace the current unofficial stream extraction playback with a compliant YouTube IFrame Player integration where feasible; test embedded playback without opening an external browser.
5. Register a Google Cloud desktop OAuth client, using a system-browser authorization flow and PKCE. Do not embed the Google login page in a WebView.
6. Use authorized YouTube Data API scopes only for subscriptions/playlists, and show a clear sign-out/revoke action.
7. Test with a Premium account *only after* the user voluntarily authorizes access. Verify whether the player actually receives Premium benefits; if not, report unsupported rather than trying to bypass advertisements.
8. Verify licensing, YouTube API Terms, branding, and the repo's AGPL obligations before release.

## Current state
- The current in-app search uses an unofficial InnerTube integration and playback stream extraction; it is not an official YouTube TV client.
- A Windows GitHub Actions workflow has been added but no successful build has been confirmed.
- Google OAuth and Premium integration have **not** been implemented.
- No user credentials are required for development or initial playback testing.

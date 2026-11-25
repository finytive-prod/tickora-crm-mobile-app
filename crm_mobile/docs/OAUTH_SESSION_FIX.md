# Mobile OAuth callback and session recovery

The login callback previously validated stored state before deduplication. A
callback delivered again after successful login encountered cleared state and
emitted `Invalid or expired login session state`, potentially replacing the
successful login result. A mismatched old callback also cleared a newer attempt.

The callback entry point now serializes deliveries from native WebView and app
links, validates the exact configured redirect endpoint and matching saved state,
and deduplicates callbacks before reading consumed state. Stale or foreign
callbacks leave the current transaction intact. Callback fingerprints are bounded
and contain no plaintext authorization codes. Repeated sign-in taps reuse the
existing attempt instead of generating a different verifier.

The native Android dialog completes its pending call once on dismissal, including
programmatic cancellation. Full authorization and callback URLs are no longer
logged by the affected flow. PKCE and state validation remain required.

Refresh-token renewal reserves its shared in-flight operation before reading
storage. Concurrent requests therefore exchange a rotating refresh token once.
Temporary failures preserve the session; known permanent Platform errors require
a fresh sign-in. An old refresh cannot restore a session after logout or after a
new browser login starts.

## Verification

Use a Flutter SDK compatible with the project's Dart constraint, then run:

```sh
flutter pub get
flutter test test/oauth_callback_lifecycle_test.dart test/auth_interceptor_test.dart
dart analyze lib/core/services/oauth_service.dart test/oauth_callback_lifecycle_test.dart
```

Regression coverage includes duplicate/concurrent callback delivery, stale state,
foreign endpoints, five successive logins, repeated taps, concurrent refreshes,
temporary failures and logout during refresh.

Build and distribute a new signed mobile release through the existing release
process. A QA backend deployment cannot update already installed mobile binaries.
Device verification must cover sign-in, cancellation, browser/app backgrounding,
logout, and sign-in again on the affected Android phone.

The seven-day session policy is supplied by the Platform authorization service
(tickora-team commit `9d6ac91`), not by extending mobile access-token validity.
Deploy that backend change and start a fresh login session to receive the new
server-side expiry. Access tokens continue to be renewed automatically.

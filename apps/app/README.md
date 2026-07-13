# alliswell (Flutter app)

The AllisWell client — **one codebase for iOS, Android, Web, macOS, Windows and Linux**.
Rules: [/AGENTS.md](../../AGENTS.md) • Architecture: [/docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md).

```bash
flutter pub get
flutter run -d chrome     # or: macos / windows / linux / an emulator / a device

# quality gates (CI runs these too)
dart format lib test
flutter analyze
flutter test
```

## Structure

```txt
lib/main.dart              entrypoint (ProviderScope + AllisWellApp)
lib/src/app.dart           MaterialApp.router + Material 3 theme (seed #2563EB)
lib/src/router.dart        go_router — StatefulShellRoute with 5 section branches + /settings
lib/src/sections.dart      AppSection enum (title/path/icons/backlog ref)
lib/src/screens/           home_shell (adaptive rail/bottom-bar), placeholders, settings
```

State management is Riverpod; screens are placeholders until their epics land
(see [/docs/TASKS.md](../../docs/TASKS.md) — Flutter work starts at OPH-024/036/037).

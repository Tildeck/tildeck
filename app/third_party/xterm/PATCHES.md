# Vendored xterm.dart

This directory is `xterm` 4.0.0 from pub.dev (TerminalStudio/xterm.dart, MIT license, see `LICENSE`), copied unchanged except for the patches below. Only `lib/`, `LICENSE`, and `pubspec.yaml` are kept.

Upstream has not published a release since 2024-02 and has not merged the fixes Tildeck needs, so the app depends on this copy through a path dependency. Drop the copy and return to the published package once upstream releases the fixes.

## Patches

1. `lib/src/ui/custom_text_edit.dart`: pass the Flutter view id in the `TextInputConfiguration`. Flutter's Windows embedder (Flutter 3.44 and later) rejects `TextInput.setClient` without it, and the terminal then drops every typed character. Upstream pull requests: TerminalStudio/xterm.dart#224, #228, #231. Covered by `app/test/terminal_input_test.dart`.

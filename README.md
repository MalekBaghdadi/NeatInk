# NeatInk — handoff pack for Claude Code

This folder is the starting point. It has the full plan; Claude Code writes the actual app inside it.

| File | What it is |
|---|---|
| `CLAUDE.md` | The main brief: rules, tech stack, architecture, data model, milestones. Claude Code reads it automatically. |
| `docs/beautify-spec.md` | The detailed algorithm for "tidy as you write" (level 3), with tests and tuning numbers. |

## Before you start (on your PC)

1. Install the **Flutter SDK** (latest stable) and **Android Studio** (for the Android SDK + platform tools). Run `flutter doctor` and fix anything red.
2. Install **Claude Code**.
3. On the MatePad, turn on **Developer options** (Settings → About tablet → tap *Build number* 7 times; on some HarmonyOS versions it's called *Software version*), then turn on **USB debugging**.
4. Connect the tablet by USB and check that `adb devices` lists it.

## Hand it off

```bash
cd neatink
git init && git add . && git commit -m "Project brief"
claude
```

Then tell Claude Code:

> Read CLAUDE.md and docs/beautify-spec.md. Ask me anything unclear, then start Milestone M0.

Go one milestone at a time. After each one, install the APK on the tablet, try the checklist Claude Code gives you, and report back what felt off. For the tidy feature, turn on the **debug overlay** (Settings → Developer) and tell Claude Code what it detected wrong.

## Installing the APK manually

`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` → copy it to the tablet, open it, and allow "install unknown apps" when asked.

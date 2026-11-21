# Hyper-Bot (Android)

A friendly, **clearly-labelled** Roblox bot for Android. A floating bubble lets you walk, jump, emote and
say your own chat lines, or turn on **Auto** to do it by itself. It always announces that it's a bot.

**Input-only:** it taps and swipes the screen like a finger would, through Android's Accessibility
service. It doesn't modify, inject into or read data from Roblox. Use it on an **alt account**.

## Install
1. Download the latest `HyperBot-build-N.apk` from this repo's **Releases** (or the Actions run).
2. Open it on your phone and allow "install unknown apps" for your browser/files app when Android asks.
3. Open **Hyper-Bot** → *Open Accessibility settings* → Installed apps → **Hyper-Bot** → On.
4. Edit your intro (must contain "bot") and chat lines → **Save** → **Show the bubble**.

## First use in Roblox
1. Join a game (landscape). Tap the **HB** bubble → **Calibrate**.
2. Drag **JOY** (joystick), **JUMP**, **CHAT** (chat icon), **BOX** (chat text box, with chat open) and
   **SEND** onto Roblox's real buttons → **Save calibration**.
3. Use the buttons, or **Auto: ON**. **STOP** stops everything.

## Built-in rules
- Intro announcing it's a bot: on start and every 10 minutes.
- Chat lines at most every 30 seconds (configurable, never faster). Emotes at most once a minute.
- No following or targeting other players.

## Build
Pushing to `main` builds the APK with GitHub Actions (`.github/workflows/build.yml`).

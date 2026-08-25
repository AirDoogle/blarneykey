# BlarneyKey

**The gift of the gab, without the trip to Blarney.**

Local push-to-talk dictation for macOS. Hold a key, speak, let go — the words appear
wherever your cursor is. No account, no network, no subscription, no per-minute pricing.
Your audio never leaves the machine.

Built by [Cork AI Consulting](https://github.com/AirDoogle) — practical AI for small Irish
businesses. Named for the Blarney Stone, a few miles up the road, which is said to grant
the gift of the gab to anyone who kisses it. This is the same idea with less bending over.

Built from public parts only: [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT)
via Homebrew, a Whisper model from Hugging Face, and Apple's public Foundation Models
framework for the optional cleanup pass — the public API Apple ships for third-party
access to the on-device Apple Intelligence model, which needs no entitlement and runs
inference locally.

## What it does

- **Push to talk** on any of 16 preset keys: left and right ⌘ ⌥ ⌃ ⇧, fn, or F13–F19.
  **Set up as many as you like** — one keyboard's spare key is another keyboard's missing
  key, so an external board and the built-in one can each have their own.
  Hold to dictate, or double-tap to lock it on for longer stretches, then tap again,
  press Escape, or hit stop on the pill.
- **Or record your own key.** Press a spare key on an external keyboard and use that.
  Keys needed for typing (letters, Return, Space, Tab, Delete, Escape) are refused
  outright; keys that merely have another job warn you first. If you do bind something
  awkward, *Reset hotkey* sits in the menu-bar menu, reachable with the mouse alone.
- **Two insertion modes.** Paste (⌘V) by default, or type the text out character by
  character for apps that refuse a synthetic paste.
- **Floating pill** while recording: live input level, elapsed time, stop button. It's a
  non-activating panel, so it never steals focus from what you're dictating into.
- **Prompts** — say "weekly business review" and it pastes the whole template. Matching
  ignores case, punctuation and messy spacing, because speech models add all three.
- **App allowlist** — restrict where dictation can paste, per app, with an *allow
  everything* switch that's on by default. On your own machine there's no reason to
  fence yourself in; turn it off if you want the discipline.
- **On-device cleanup** — optionally polish transcripts with Apple Intelligence to
  fix punctuation and drop filler words. Local, and per-app or everywhere. It refuses a
  result that's wildly longer or shorter than the input, which is how you catch the model
  *answering* your dictation instead of tidying it.
- **Dashboard** — words, sessions, time saved against a typing baseline you set, speaking
  speed, day streak, and a history grouped by day with per-app filters and a copy button
  on every line.
- **Nothing is ever lost.** If a paste is blocked, the text goes to the clipboard and the
  menu bar tells you why.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/AirDoogle/blarneykey/main/install.sh | bash
```

That checks your Mac, installs the speech engine from Homebrew, downloads the model,
builds the app, installs it to `/Applications` and opens it. Five to ten minutes, most of
it the 1.4 GB model download.

Then grant one permission — **System Settings → Privacy & Security → Accessibility** — and
hold Right ⌥ to talk. The app shows a banner with a button until you do.

**Requirements:** Apple Silicon, macOS 15+, [Homebrew](https://brew.sh), and the Xcode
command line tools (`xcode-select --install`).

### Why it builds instead of downloading a ready-made app

Apple charges $99 a year for the Developer ID certificate that lets a Mac app be signed and
notarized. Without one, any prebuilt app downloaded from the internet is quarantined by
Gatekeeper and refuses to open until you dig through System Settings to allow it — and the
usual "fix" going round is a command that strips that protection, which is not something you
should paste on a stranger's say-so.

Building on your own machine avoids the whole problem. Nothing arrives as an untrusted
binary, so there is nothing to override and no security check to disable. The cost is the
command line tools and a few minutes of compiling.

## Requirements

- Apple Silicon Mac (the speech model runs on the Neural Engine)
- macOS 15 or later; macOS 26 for the optional Apple Intelligence cleanup pass
- [Homebrew](https://brew.sh) and the Xcode command line tools (`xcode-select --install`)
- About 1.5 GB of disk for the speech model

## Manual setup

```bash
git clone https://github.com/AirDoogle/blarneykey.git ~/Developer/blarneykey
cd ~/Developer/blarneykey
./setup.sh
open /Applications/BlarneyKey.app
```

`setup.sh` installs `whisperkit-cli` from Homebrew, downloads the model from Hugging Face
(~1.4 GB), assembles it, tests the engine, and builds the app. **Download the model rather
than copying one across from another machine** — it's a public artifact and a fresh
download keeps things unambiguous.

Two one-time permission prompts:

1. **Microphone** — accept the dialog.
2. **Accessibility** — needed to see the hotkey while other apps are focused, and to
   paste. There's a menu item that takes you straight to the settings pane.

## Everyday use

The menu bar icon is the status: waveform idle, red mic recording, dots transcribing,
orange triangle when something went wrong (the menu says what). `⌘O` opens the window,
`⌘D` starts and stops dictation without the hotkey.

Settings live in the window, not in `defaults`. Everything is stored in
`~/Library/Application Support/BlarneyKey/state.json` — settings, allowlist, prompts and
history, one readable file you can back up or edit.

## How it fits together

| File | Job |
|---|---|
| `HotKeyMonitor` | Press/release/double-tap plus Escape, for modifiers and ordinary keys alike. Modifier direction comes from the device-dependent flag bit, which is also what separates the right-hand key from the left |
| `Recorder` | `AVAudioRecorder` straight to 16 kHz mono WAV, the format Whisper wants, with no sample-rate plumbing to get wrong |
| `Transcriber` | Runs `whisperkit-cli`; stdout is the transcript and nothing else |
| `PromptEngine` | Normalises case, punctuation and spacing, then matches whole utterances only |
| `Cleanup` | Foundation Models polish, with a sanity check on the result |
| `TextInserter` | Clipboard plus a synthesised ⌘V chord, then restores your clipboard; or direct Unicode typing |
| `DictationController` | Sequences all of the above and writes the history entry |
| `Store` | One JSON file, plus the stats derived from it |
| `Views/` | SwiftUI: Home, Prompts, Settings (Apps lives inside Settings) |

**Why the ⌘V chord is sent as four events:** setting `.maskCommand` on the V keypress is
enough for native AppKit apps, but Chromium-based ones — Notion, Slack, VS Code, Discord —
track modifier state from the modifier *key events* themselves. Without a genuine ⌘ keyDown
they see a bare "v" and discard it, so nothing pastes. `TextInserter` sends ⌘ down, V down,
V up, ⌘ up with a few milliseconds between each.

**Why no warm-model server:** the first build used `whisperkit-cli serve` to keep the
model resident. Measured, a 14-second utterance round-trips in about **1.3 seconds
including model load**, because CoreML caches the compiled model. So the server, its
LaunchAgent and the HTTP layer all came out. Simpler wins.

## Choosing a different model

`distil-large-v3` is the speed/accuracy sweet spot. To try another:

```bash
./setup.sh large-v3 openai      # <model-name> <prefix: openai|distil>
```

The tokenizer files must end up in the model directory. Without them `whisperkit-cli`
tries to fetch them from Hugging Face at runtime and fails on a restricted network.

## Start at login

Settings → General → **Start at login**. It registers the app with macOS through
`SMAppService`, so it also appears in System Settings → General → Login Items, where you
can revoke it. The app checks the real state at launch rather than trusting its own
setting, so switching it off there is reflected next time you open it.

There is nothing to configure for waking from sleep: waking does not quit anything, so
BlarneyKey is still running. A restart is the only thing that stops it, and that is what
this covers.

## Stable signing

macOS ties an app's Accessibility permission to its **designated requirement**. Signed
ad-hoc there is no certificate, so that requirement falls back to the code hash, which
changes on every single build. The result is nasty: the app appears ticked in Privacy &
Security while the entry authorises nothing, dictation keeps recording, and the paste
silently does nothing.

`build.sh` avoids this by signing with a real certificate when it finds one. It looks for,
in order: `$BLARNEYKEY_SIGNING_IDENTITY`, a `BlarneyKey Self-Signed` certificate, a
`Developer ID Application`, then an `Apple Development` certificate. Signed that way the
requirement becomes the bundle identifier plus the certificate, and rebuilds stop breaking
the grant.

Check what you have:

```bash
security find-identity -v -p codesigning
```

**An `Apple Development` certificate is free** and comes with any Apple ID: open Xcode →
Settings → Accounts, add your Apple ID, and it issues one. If Xcode has ever built anything
on the machine, it is probably there already. That is all this needs; the $99 Developer
Program is only required to *distribute* a signed app to other people.

**If you would rather not involve an Apple ID,** make a self-signed certificate instead.
Keychain Access → Certificate Assistant → Create a Certificate. Name it
`BlarneyKey Self-Signed`, set Identity Type to **Self Signed Root** and Certificate Type to
**Code Signing**, then create it. `build.sh` picks it up by name.

Either way, the switch changes the designated requirement once, so **re-grant Accessibility
one final time** after the first signed build. It holds from then on.

## Rebuilding

`./build.sh` recompiles, reinstalls to `/Applications` and re-signs. With a signing
certificate in place (see above) the Accessibility grant survives. Without one it does not,
and the script says so loudly every time.

## When something breaks

Check the engine on its own first:

```bash
say -o /tmp/t.wav --data-format=LEF32@16000 "one two three"
whisperkit-cli transcribe --model-path ~/Developer/blarneykey/models/combined \
  --model-prefix distil --audio-path /tmp/t.wav --without-timestamps --skip-special-tokens
```

If that prints the words, the engine is fine and the problem is the app or its
permissions.

**Dictation records but nothing appears.** The history in the Home tab will show the
transcript with no error, which means the paste was attempted and the app ignored it.
Switch Settings → Insertion to **Type it out**. App logs go to the system log:

```bash
log stream --predicate 'process == "BlarneyKey"' --level default
```

## Provenance and licences

Everything here is either written for this project or a public, permissively licensed
component. Nothing is derived from anyone's private or internal software.

| Part | Origin | Licence |
|---|---|---|
| The app itself | Written for this project | MIT (see `LICENSE`) |
| `whisperkit-cli` | [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift), installed from Homebrew | MIT |
| distil-whisper `distil-large-v3` | Downloaded from Hugging Face at install time | MIT |
| Foundation Models framework | Apple's public macOS SDK, for the optional cleanup pass | Apple SDK terms, no entitlement needed |
| App icon | Generated from the prompt in `assets/LOGO_PROMPT.md` | This project |
| Cork AI Consulting mark | Cork AI Consulting's own logo | Cork AI Consulting |

The app declares **no Swift package dependencies**, links **only public frameworks**, uses
**no private API** (no `dlopen`, no `NSClassFromString`, no underscored symbols), and ships
**no entitlements** beyond the microphone usage string. The speech model is never
redistributed: `setup.sh` fetches it from Hugging Face on the machine it will run on.

## Licence

MIT — see [LICENSE](LICENSE). Do what you like with it.

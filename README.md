# TwoUp

*(formerly BTPhone — bundle id `com.wahdany.twoup`, service `_twoup._udp`;
only the Xcode target and this repo keep the old working name)*

A rider/passenger intercom for two iPhones. The phones talk **directly to each
other over Wi-Fi Aware** (iOS 26's peer-to-peer Wi-Fi framework) — no
internet, no SIM, no router. The link is paired, authenticated, and encrypted
by the system, runs in Wi-Fi Aware's real-time performance mode, and — unlike
the AirDrop-style AWDL transport this app used originally — **keeps working
with the phone locked in your pocket**, because it only requires the app to
be running (which the audio background mode guarantees), not frontmost.

Audio is uncompressed 16 kHz voice PCM over UDP with a small self-trimming
jitter buffer, tuned for low latency. Voice processing (echo cancellation,
noise suppression, auto gain) comes from Apple's voice-processing audio unit.

## Requirements

- Two iPhones on **iOS 26 or later** (Wi-Fi Aware hardware support; the app
  checks at runtime and tells you if a phone can't do it).
- A **paid** Apple Developer account for building (the Wi-Fi Aware
  entitlement is self-service, but not available to free personal teams).

## Build & install

```sh
# Generate the Xcode project (once, and after editing project.yml)
nix-shell -p xcodegen --run "xcodegen generate"
open BTPhone.xcodeproj
```

The team ID is set in `project.yml`; plug in each iPhone (Developer Mode
enabled) and Run once per phone. Approve the microphone prompt on first
launch.

## Usage

1. Pair each phone with its own helmet headset **before** starting the app.
   TwoUp requests HFP (hands-free) routing so the helmet's boom mic is used.
2. **One-time pairing:** open TwoUp on both phones; on one tap
   *Be discoverable*, on the other tap *Find other phone* and select it.
   The pairing persists (manage it in iOS Settings if you ever want to
   remove it).
3. Wait for "Connected" + green. Tap the big button to mute/unmute. While
   muted, the other phone shows "The other phone is muted" instead of a
   connection warning.
4. Lock the phone and pocket it — the link and audio keep running.

## Free tier & unlock

Sessions are free but end after 15 minutes (restart as often as you like);
a one-time lifetime unlock (StoreKit 2 non-consumable, Family Sharing)
removes the limit. The gate fails open: until the product exists in App
Store Connect — including all dev builds — nothing is limited. The local
`Configuration.storekit` file feeds Xcode's StoreKit test environment when
running via the scheme. UI ships localized in English and German
(`Localizable.xcstrings`).

## Field results

First real ride (July 2026, rider + passenger, phones locked in pockets,
Bluetooth helmet headsets): a session of ~350,000 received packets — just
under two hours of continuous audio at 50 packets/s — with battery drain low
enough that neither phone noticed it. Precise %/hour and open-road range
numbers still to be collected.

## Wire protocol

20 ms frames: 4-byte big-endian sequence number + 320 samples of 16 kHz mono
Int16 PCM per UDP datagram (~50 packets/s). An empty payload is a mute
keepalive (2/s) so the peer can distinguish "muted" from "gone". A 60 ms
jitter buffer smooths playback and trims itself back down after bursts and
clock drift; mouth-to-ear latency is roughly 100–150 ms phone-to-phone plus
whatever the Bluetooth helmet headsets add (HFP typically 50–100 ms per side).

## Troubleshooting

- **"Pair with the other phone to start" won't go away:** the phones aren't
  paired yet — run the one-time pairing (step 2 above). Both phones need
  Wi-Fi (and preferably Bluetooth) radios on.
- **Choppy audio:** check the loss % in the footer (it's a 10-second window).
  Sustained loss above a few percent means radio trouble — distance or heavy
  2.4/5 GHz congestion.
- **Wrong mic in use:** iOS picks the route; reconnecting the headset while
  TwoUp is open makes it re-route — the app rebuilds its audio pipeline
  automatically on route changes, and a watchdog revives audio if anything
  kills it (the big button shows AUDIO OFF whenever audio isn't actually
  running).
- **New passenger or new phone:** tap *Pair a different phone* in the status
  card — the pairing UI is always reachable. Old pairings can only be
  removed in iOS Settings (there is no unpair API).
- **Music:** playback from other apps pauses while a session runs and
  resumes automatically when you end it. Mixing music into the session isn't
  offered: over a Bluetooth helmet headset the intercom holds the HFP voice
  link, which blocks high-quality A2DP — music would be call-quality mono.
- **Battery:** real-time Wi-Fi Aware mode plus continuous audio costs some
  battery, but you can ride with the screen locked, which more than makes up
  for it.

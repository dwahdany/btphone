# BTPhone

A rider/passenger intercom for two iPhones. The phones talk **directly to each
other over peer-to-peer Wi-Fi** (AWDL, the same radio link AirDrop uses) — no
internet, no SIM, no router needed. Audio is uncompressed 16 kHz voice PCM
over UDP with a small jitter buffer, tuned for low latency rather than
robustness over distance. Range is roughly what AirDrop manages: more than
enough for rider + passenger on one motorcycle.

## How it works

- Both phones advertise and browse the Bonjour service `_btphone._udp` with
  `includePeerToPeer` enabled (Network.framework). No pairing, no roles: start
  the app on both phones and they find each other.
- Audio runs through Apple's voice-processing I/O unit, so you get echo
  cancellation, noise suppression, and automatic gain control for free.
- Each mic frame (20 ms) is sent as one UDP datagram with a sequence number.
  A 60 ms jitter buffer smooths playback; total mouth-to-ear latency is
  roughly 100–150 ms phone-to-phone, plus whatever your Bluetooth helmet
  headsets add (HFP typically adds another 50–100 ms).

## Build & install

```sh
# Generate the Xcode project (once, and after editing project.yml)
nix-shell -p xcodegen --run "xcodegen generate"
open BTPhone.xcodeproj
```

In Xcode: select the **BTPhone** target → *Signing & Capabilities* → pick your
team. Plug in each iPhone (Developer Mode must be enabled: Settings → Privacy
& Security → Developer Mode) and Run once per phone. With a free Apple ID the
install expires after 7 days; a paid developer account gives you a year.

## Usage

1. Pair each phone with its own helmet headset **before** starting the app.
   BTPhone requests HFP (hands-free) routing so the helmet's boom mic is used.
2. Open BTPhone on both phones. Approve the microphone and **Local Network**
   prompts on first launch (both are required).
3. Wait for "Connected" + green. Tap the big button to mute/unmute. While you
   are muted the other phone shows "The other phone is muted" instead of a
   connection warning.

**Keep the app in the foreground with the screen on** (it disables auto-lock
itself). This is a hard requirement, not a preference: iOS throttles or stops
peer-to-peer Wi-Fi (AWDL) when the app leaves the foreground or the screen
locks, even though the app declares background audio. Background audio only
helps it survive a few seconds of app switching. Pocket use works fine with
the screen on; turn brightness down to save battery.

BTPhone does no pairing: the first two phones running the app find each other
by service name. Don't ride with a third phone running BTPhone nearby — it
can capture one side of the conversation.

## Troubleshooting

- **Phones don't find each other:** Wi-Fi and Bluetooth must be *enabled* on
  both phones (no network connection required, just the radios). Check
  Settings → Privacy & Security → Local Network → BTPhone is allowed. Then
  tap *Restart connection* on both.
- **Choppy audio:** check the loss % in the footer. Loss above a few percent
  usually means the phones are too far apart or the 2.4/5 GHz band is noisy.
- **Wrong mic in use:** iOS picks the route; reconnecting the headset (or
  toggling Bluetooth) while BTPhone is open makes it re-route — the app
  rebuilds its audio pipeline automatically on route changes.

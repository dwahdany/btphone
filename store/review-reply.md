# Reply to App Review — Guideline 2.1 information request

Paste into the Resolution Center reply (App Store Connect → TwoUp → App
Review). Item 1 (screen recording) must be attached as a video file — shot
list below.

---

Thank you for the review. Here is the requested information.

**1. Screen recording**

Attached — a screen recording captured on a physical iPhone 16 Pro
(iOS 26.5). Note that TwoUp is a live voice intercom between TWO iPhones (a
motorcycle rider and passenger); a second physical iPhone is paired and
active just off-screen, and its user's live voice can be heard playing
through the recorded device during the session. The recording shows: cold
launch, the microphone permission prompt (the app's only system
permission), the one-time pairing flow (Apple's DeviceDiscoveryUI), START,
a live connected session with the peer's speech audibly playing and the
packet counter advancing, the mute toggle, the in-app purchase paywall
(reached from "Unlock unlimited sessions") with the €9.99 lifetime unlock
and the Restore Purchases button, and ending the session.

**2. Devices and operating systems tested**

- iPhone 16 Pro, iOS 26.5 (physical device)
- iPhone 16, iOS 26.5 (physical device)
- Real-world field testing: ~2-hour continuous sessions on motorcycle rides
  with Bluetooth helmet headsets, phones locked in pockets
- UI additionally verified on the iPhone 17 Pro Max simulator (note: Wi-Fi
  Aware does not run in the Simulator; all functional testing was on the
  physical devices above)

**3. Purpose and target audience**

TwoUp lets a motorcycle rider and passenger talk to each other while
riding. Dedicated motorcycle intercom hardware costs €70–700 per pair;
existing app alternatives require a cellular internet connection, which
fails in tunnels, mountains, and abroad (roaming). TwoUp solves this by
connecting the two iPhones the couple already owns DIRECTLY to each other
using the Wi-Fi Aware framework (iOS 26): full-duplex, echo-cancelled voice
with no internet, no SIM, no server, and no account, working with both
phones locked in the riders' pockets, using the Bluetooth helmet headsets
they already own. Target audience: motorcycle riders with passengers; the
same setup works for cyclists, boaters, and skiers. Audience is 4+ (no
objectionable content).

**4. Setup instructions**

No accounts, logins, or sample files exist. You need two iPhones with
Wi-Fi Aware support (iPhone 12 or later class hardware) on iOS 26+:

1. Install TwoUp on both devices; launch and grant the microphone
   permission on both.
2. One-time pairing: on one phone tap "Be discoverable", on the other tap
   "Find other phone", select the peer, confirm the system pairing dialog.
3. Tap the big blue START button on both phones. Within a few seconds the
   status shows "Connected" and the button turns green (LIVE). Speak into
   either phone; the voice plays on the other.
4. Lock both phones — the session continues (audio background mode).
   Tap the big button to mute; "End intercom" ends the session and releases
   the microphone.
5. Purchase flow: while a free session runs, tap "Unlock" next to the
   session countdown (or wait for the 15-minute limit) to see the paywall
   with the one-time €9.99 unlock and Restore Purchases.

**5. External services, tools, and platforms**

None. There is no server component, no data provider, no authentication
service, no analytics, no advertising, and no AI service. Voice audio
travels exclusively device-to-device over the Wi-Fi Aware peer link,
encrypted by the system pairing. The only external service is Apple's own
StoreKit / App Store for the single non-consumable in-app purchase. The app
is open source: https://github.com/dwahdany/btphone

**6. Regional differences**

None. The app functions identically in all regions — it uses no
region-dependent services (nothing requires internet at all). The UI and
App Store listing are localized in English and German; functionality is
identical in both.

**7. Regulated industry / third-party material**

Not applicable. TwoUp contains no third-party content and does not operate
in a regulated industry. All audio is the users' own live speech, never
recorded or stored.

---

## Shot list for the screen recording (item 1)

Single-device iOS screen recording (Control Center, microphone option OFF —
the app owns the mic during a session; incoming audio is captured as app
audio automatically). 60–90 seconds, one take, on the iPhone 16 Pro. The
second phone sits nearby, freshly launched, with someone to speak into it.

1. Start recording on the home screen → launch TwoUp
2. Mic permission prompt → Allow (reset beforehand via delete/reinstall or
   Settings → Privacy → Microphone)
3. Pairing card → "Find other phone" → select the peer → confirm the
   system dialog (peer taps "Be discoverable" off-screen)
4. Tap START → "Connected to …", button green LIVE
5. The other person speaks into their phone → their voice audibly plays in
   the recording, packet counter climbing
6. Big button → MUTED (red) → tap again → LIVE
7. "Unlock" beside the free-session countdown → paywall sheet
   ("Unlock forever — €9.99", "Restore Purchases") → "Not now"
8. "End intercom"

Optional bonus for the reviewer (not required): a short camera clip of both
phones side by side, or of the locked-phones-in-pocket use case.

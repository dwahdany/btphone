# User stories & edge cases

*Audited 2026-07-12 against the code and the iOS 26 WiFiAware SDK. Items
marked ✅ are handled in the app today; ⚠ are verified-open questions.*

## Pairing to a different partner (new passenger, friend's phone)

✅ Fixed: the status card now always offers **"Pair a different phone"**, so
the pairing UI stays reachable after the first pairing. The SDK has **no
unpair API** (verified: `WAPairedDevice` exposes none) — removal is
iOS-Settings-only, and the pairing card says so.

⚠ Multiple pairings are legal and the app connects to *whichever paired
phone responds first* (`endpoints.first`, last inbound wins). With two
paired phones in range you could silently talk to the wrong one. The app now
shows a persistent hint when more than one device is paired. A per-device
picker (`.selected(_:)` exists in the SDK) is the proper future fix.

⚠ The exact iOS Settings path for removing a pairing is unconfirmed
(candidates: Settings → Privacy & Security → Accessories / Pairing) — check
on-device before writing it into user-facing docs.

## Group calls (3+ riders)

Future feature, significant rework: the architecture is strictly 1:1 (one
inbound + one outbound flow, one jitter buffer). Multi-peer needs N retained
connections, per-peer sequence tracking, and an audio mixer, bounded by
`WACapabilities.maximumConnectableDevices`. Until then: the app is built for
exactly two phones.

## New phone / migration

- The Wi-Fi Aware pairing almost certainly does **not** survive a device
  migration (key material is device-bound, like Bluetooth pairings) — the
  new phone simply re-pairs. ⚠ Unverified against Apple docs.
- The rider who *kept* their phone uses "Pair a different phone" (the old
  stale pairing can be removed in Settings).
- The lifetime unlock is Apple-ID-based and survives migration; worst case
  one tap on Restore Purchases.

## Restoring purchases

✅ The paywall has a Restore Purchases button (`AppStore.sync()` — required
by App Review 3.1.1). Family members unlock automatically via
`Transaction.currentEntitlements` (family-shared transactions are included);
refunds/leaving the family group re-lock automatically via
`Transaction.updates`. Test case before launch: partner's device with the
purchaser's family group, fresh install, airplane mode after first unlock.

## Incompatible partner (Android, iOS < 26, no Wi-Fi Aware hardware)

- Own phone unsupported → honest "This iPhone doesn't support Wi-Fi Aware".
- Partner incompatible/absent → ✅ after 20 s of fruitless searching the app
  now hints "Can't find the other phone…". There is no cross-device
  capability signaling, so it can't know *why*.
- Store listing must say clearly: **both** riders need a Wi-Fi-Aware-capable
  iPhone on iOS 26+ (done in store/metadata-*).

## Mid-ride events

- Phone call / Siri on one phone: audio pauses there, link stays up; the
  other rider sees "No audio from the other phone — maybe a call or Siri"
  (✅ softened copy) and everything self-heals when the call ends.
- Wi-Fi off / airplane mode: link drops to "Searching…", recovers by itself
  when the radio returns; the 20 s hint nudges toward Wi-Fi.
- Out of range and back / peer battery dies: ACK-liveness tears the dead
  flow down within ~10 s and re-browses once a second; reconnection is
  automatic.
- ⚠ Low Power Mode: effect on real-time Wi-Fi Aware unverified; advise
  riders to disable it for best latency.

## First run

- Mic permission denied → ✅ explanation plus an "Open Settings" button
  (toggling the permission relaunches the app, which then starts cleanly).
- Both riders tap the *same* pairing button → soft deadlock (both publish or
  both browse; nothing errors). The card's copy assigns the roles; a guided
  one-button flow is a possible future refinement.

## Music during a session

Starting a session pauses any playing music (the audio session is
deliberately non-mixable), and ending it resumes the music automatically
(`notifyOthersOnDeactivation`). Mixing music *into* the session
(`.mixWithOthers` + voice-processing ducking) is technically possible but of
limited value over a Bluetooth helmet headset: while the intercom holds the
HFP/SCO voice link, the headset cannot run A2DP, so music would be forced
into call-quality mono. Hardware intercoms solve this in firmware. Verdict:
document now, optional "mix music (call quality)" toggle later.

## Long-term smaller items

- App updates keep the pairing (it lives in iOS, not app storage). ✅
- ⚠ "Offload Unused Apps" over winter: unknown whether the pairing record
  survives; if not, re-pairing takes a minute in the driveway.
- Portrait-only UI: fine in a pocket, suboptimal in a landscape handlebar
  mount. Future.
- Screen Time restrictions can block the mic or the app — standard behavior,
  nothing app-specific.

# App Review notes (paste into App Store Connect "Notes" field)

TwoUp is a live full-duplex voice intercom between two iPhones for a
motorcycle rider and passenger. The two phones connect DIRECTLY to each
other over Wi-Fi Aware (the iOS 26 framework); there is no server component.

TESTING REQUIRES TWO PHYSICAL DEVICES
Wi-Fi Aware does not run in the Simulator. To test: install on two iPhones
(iOS 26+), open the app on both, tap "Be discoverable" on one and "Find
other phone" on the other to pair (one time), then tap START on both. Speak
into one phone; the voice plays on the other with ~150 ms latency. A demo
video is provided in the review attachment showing the full flow.

BACKGROUND AUDIO JUSTIFICATION
The app declares the `audio` background mode because its core function is an
ongoing two-way voice session, equivalent to a VoIP call: riders lock their
phones and put them in their pockets for the whole ride. Audio capture and
playback (and the peer-to-peer link, which iOS keeps alive as long as the
app runs) must continue while the device is locked. The microphone is active
only during a user-started intercom session, indicated by the system mic
indicator; the END button releases the microphone and the audio session.

ENTITLEMENT
The app uses the self-service Wi-Fi Aware entitlement
(com.apple.developer.wifi-aware: Publish, Subscribe) with the matching
WiFiAwareServices Info.plist declaration (`_twoup._udp`).

IN-APP PURCHASE
Free tier: each intercom session is limited to 15 minutes (unlimited
restarts). One non-consumable "Lifetime Unlock" (Family Sharing enabled)
removes the limit. A Restore Purchases button is on the paywall. If the
StoreKit products cannot be loaded, the app fails open (no session limit)
rather than locking the user out.

PRIVACY
No data is collected — no servers, no accounts, no analytics. Voice audio is
transmitted only device-to-device, encrypted by the Wi-Fi Aware pairing.
Privacy policy: https://github.com/dwahdany/btphone/blob/main/PRIVACY.md

# App Store featuring nomination (App Store Connect → Featuring Nominations)

Submit ~3 months before launch (target launch: early September 2026 → submit
now). Fields below map to the nomination form.

## App

TwoUp: Motorcycle Intercom — iPhone, iOS 26.0+

## Nomination type

App launch (new app)

## Expected release date

Early September 2026

## What makes it innovative

TwoUp is among the first consumer apps built on **Wi-Fi Aware**, the
peer-to-peer framework Apple opened up in iOS 26 — and the first live voice
application on it. Two iPhones become a full-duplex motorcycle intercom with
no internet, no server, and no dedicated hardware: encrypted phone-to-phone
audio at ~150 ms latency that keeps running with both phones locked in the
riders' pockets, something that was impossible with any previous iOS
peer-to-peer transport.

It replaces €200–700 of dedicated intercom hardware with the iPhones a
couple already owns plus the Bluetooth helmet headsets they already ride
with.

## Technologies used

- **Wi-Fi Aware** (WAPairedDevice, real-time performance mode, publisher +
  subscriber datapaths) — system-paired, mutually authenticated, encrypted
- **Network framework** (the new NetworkConnection/NetworkListener/
  NetworkBrowser API) with UDP and the interactive-voice service class
- **DeviceDiscoveryUI** (DevicePairingView / DevicePicker) for one-tap pairing
- **AVAudioEngine** with the voice-processing I/O unit (echo cancellation,
  noise suppression, AGC) and a custom self-trimming jitter buffer
- **SwiftUI**, StoreKit 2 (one-time unlock with Family Sharing)

## The story

A German indie developer built it for himself and his passenger because
every existing option either needs cellular data (dead in tunnels and
mountains, roaming abroad) or costs hundreds of euros in strap-on hardware.
Privacy is structural: the voice path is phone-to-phone with literally no
server, and the app is open source. The EU angle: Wi-Fi Aware's arrival on
iOS is connected to the DMA's interoperability requirements — this is the
kind of app that access made possible.

## Accessibility / audience

Glove-sized controls designed to be operated with motorcycle gloves; honest
connection-state UI readable at a glance in a tank-bag mount. One purchase
covers the couple via Family Sharing.

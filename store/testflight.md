# TestFlight & beta recruitment

## Beta App Description (TestFlight)

```
TwoUp turns two iPhones into a motorcycle rider–passenger intercom. The
phones connect directly to each other over Wi-Fi Aware (iOS 26) — no
internet, no SIM, no server — and keep talking with both phones locked in
your pockets. Use the Bluetooth helmet headsets you already own.

You need: two iPhones on iOS 26+, each paired to its own helmet headset.
Pair the phones once in the app (Be discoverable / Find other phone), tap
START on both, ride.

What to test on real rides:
• Audio quality and latency through YOUR helmet headsets (tell us the model!)
• How far the link stretches (rider–passenger is easy; bike-to-bike at a
  light?)
• Battery use over a full ride (Settings → Battery, screenshot appreciated)
• Recovery: does audio come back by itself after tunnels, phone calls,
  Siri, or one phone rebooting?
• Anything that required touching the phone mid-ride — it shouldn't.

Feedback via TestFlight or GitHub: https://github.com/dwahdany/btphone
```

## What-to-test (per-build notes, first build)

```
First public beta. Focus: pairing flow on fresh installs, session start/end
(END button releases the mic), 15-minute free-session behavior, and
locked-phone pocket rides. Known good: ~2 h continuous session, negligible
battery.
```

## Recruitment post — English forums (ADVRider "cheap intercom" threads, r/motorcycles)

> **I built a free rider↔passenger intercom that's just two iPhones — no
> internet, works locked in your pockets. Beta testers wanted.**
>
> My passenger and I didn't want to spend €200+ on a Cardo/Sena setup just to
> talk to each other, so I built an iOS app that connects two iPhones
> *directly* over Wi-Fi Aware (new in iOS 26 — think AirDrop's radio, but
> pairable and it keeps running with the screen locked). Voice goes
> phone-to-phone, encrypted, no cell service needed — tunnels and mountains
> don't matter. You use whatever Bluetooth helmet headsets you already have.
>
> Field-tested on our own bike: a ~2-hour ride barely moved the battery.
> Full-duplex (no push-to-talk), echo-cancelled, auto-reconnects after
> dropouts.
>
> Needs two iPhones on iOS 26+. It's free to test, and the app is open
> source (github.com/dwahdany/btphone). TestFlight link: https://testflight.apple.com/join/6Sm5XtNR. I'd love to
> know how it does with your headsets and on your rides.

## Recruitment post — German (motor-talk.de "Gegensprechanlage" threads)

> **Kostenlose Fahrer/Sozius-Gegensprechanlage aus zwei iPhones — ohne
> Internet, läuft mit gesperrtem Handy in der Tasche. Beta-Tester gesucht.**
>
> Meine Sozia und ich wollten keine 200 € für Cardo/Sena ausgeben, nur um
> uns auf dem Motorrad zu unterhalten. Also habe ich eine iOS-App gebaut,
> die zwei iPhones *direkt* über Wi-Fi Aware verbindet (neu in iOS 26).
> Die Stimme geht verschlüsselt von Handy zu Handy — kein Mobilfunk nötig,
> Tunnel und Berge egal, kein Roaming im Urlaub. Ihr nutzt die
> Bluetooth-Helm-Headsets, die ihr schon habt.
>
> Auf unserer eigenen Maschine getestet: eine ~2-Stunden-Tour hat den Akku
> kaum belastet. Vollduplex (kein Push-to-Talk), Echounterdrückung,
> verbindet sich nach Abbrüchen selbst neu.
>
> Voraussetzung: zwei iPhones mit iOS 26+. Kostenlos, Open Source
> (github.com/dwahdany/btphone). TestFlight: https://testflight.apple.com/join/6Sm5XtNR. Rückmeldungen zu euren
> Headsets und Strecken sind Gold wert.

## Checklist to go live

- [x] App Store Connect: app record 6790109864 (bundle id com.wahdany.twoup)
- [x] Build 1.0 (1) uploaded via `xcodebuild -exportArchive` (manual signing,
      profile "TwoUp App Store" created through the ASC API)
- [x] Public TestFlight link (group "Riders"):
      https://testflight.apple.com/join/6Sm5XtNR
- [ ] Beta App Review: needs a contact phone number in the beta review
      details, then submit the build — the public link works only after
      approval
- [ ] Record the 30-second demo video (two helmets, one take)
- [ ] Post in ONE existing thread per community, answer questions daily

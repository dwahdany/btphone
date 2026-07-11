# TwoUp — naming, positioning & go-to-market

*Working doc, July 2026. Research-grounded (App Store, forums, press, pricing
checked 2026-07-11); re-verify anything marked ⚠ before acting on it.*

## The opportunity

**There is no working offline phone-to-phone motorcycle intercom on the App
Store.** The only attempt ("Rider Phone") is abandoned at 2.0 stars. Every
alternative requires cellular data and gets the same complaints in reviews:
dead in mountains/tunnels, roaming costs, must keep the app foregrounded,
battery drain — each one is a property this app inverts by design.

- Zello: 4.6★/35k ratings, internet PTT, "useless without signal"
- BlinkTalk: internet, $39.99/yr, almost no ratings
- Sena RideConnected: free, crashes, foreground-only, ~£1/hr roaming data
- Uniq Intercom: funded, subscription, runs a dedicated **"Pillion Intercom"
  SEO landing page** — paying to capture demand for exactly this use case,
  while being unable to deliver the offline part

Hardware anchor a pillion couple actually considers: Cardo Spirit Duo ~€190,
Sena 5S Dual ~€270, budget Chinese 2-packs (Lexin/EJEAS/Fodsports) $70–135.
Mesh flagships (Packtalk Edge Duo ~$720, Sena 60S Evo Dual $879) are group-ride
overkill for two-up.

## Name

**Primary: TwoUp** — App Store name "TwoUp: Motorcycle Intercom".

- "Riding two-up" *is* the use case; short, spoken-word friendly.
- `two-up.app` unregistered (DNS-checked ⚠ re-verify at registrar).
- A golf app named "Two Up" exists — the no-space "TwoUp" + subtitle keeps the
  App Store name unique.
- Quirk: two-up is an Australian ANZAC-Day gambling game. Harmless.
- ⚠ Run EUIPO/USPTO trademark clearance before committing.

Runners-up (verified clean 2026-07-11):

| Name | For | Against |
|---|---|---|
| PillionTalk | Cleanest availability of all candidates (`pilliontalk.app`/`.com` free, zero collisions) | "Pillion" opaque in US/DE; the 2025 A24 film *Pillion* dominates search with an unrelated biker association |
| LidTalk | "Lid" = biker slang for helmet; `lidtalk.app` free | Slightly cutesy; UK-leaning slang |

Avoid: bare "Pillion" (pillion.app is an active Yamaha dash-casting app),
"LidLink" (Sena sells "HelmLink"), "RideLine" (RideLink GmbH ships a German
motorcycle app one letter away), "Tandem" (ChatterBox Tandem Pro is an
existing rider-passenger intercom product). Drop "BTPhone": it implies
Bluetooth — the technology being replaced.

## App Store copy

**Subtitle (≤30 chars):** `Rider–passenger intercom`

**One-liner:** The motorcycle intercom already in your pocket.

**Description draft:**

> Talk to your passenger — clearly, hands-free, and without buying €200 of
> intercom hardware.
>
> TwoUp connects two iPhones directly to each other over Wi-Fi Aware. No
> internet, no SIM, no servers, no account: your voice goes phone-to-phone,
> encrypted, and never touches a network. It works in tunnels, in the
> mountains, abroad without roaming — anywhere two iPhones are.
>
> • Use the Bluetooth helmet headsets you already own (or any headset)
> • Full-duplex conversation with echo cancellation and noise suppression —
>   talk naturally, no push-to-talk
> • Keeps working with both phones locked in your pockets
> • Pair once; connects automatically every ride and heals itself after
>   dropouts
> • Glove-sized mute button, honest connection status, no subscription
>
> Requires two iPhones (iPhone 12 or later) on iOS 26+, one per helmet.
> Built for rider and passenger on one motorcycle.

**Keywords:** motorcycle intercom, helmet communication, pillion, passenger,
sozius, gegensprechanlage, rider, two-up, offline walkie talkie

## Positioning

Don't compete with Cardo/Sena mesh systems — compete with **the decision to
buy hardware at all**. Pitch: two cheap HFP helmet headsets (€25–50 each,
useful for music/calls anyway) + this app ≈ the full experience for a couple,
under the price of even the budget 2-packs, with nothing extra to charge or
strap on.

Privacy is a real differentiator, stated plainly: *your voice never leaves
the two phones — there are no servers to leave to.* (Open source backs the
claim.)

## Pricing

Free download, 15-minute session limit, **one-time lifetime unlock €9.99 with
Family Sharing enabled** — one purchase covers the couple.

- The trial answers "will it work with our helmets?" before paying.
- "No subscription" is a differentiator (BlinkTalk $39.99/yr, Uniq sub-only).
- Sits far below the ~$70 hardware floor.

## The press asset

Wi-Fi Aware got a wave of announcement coverage in June 2025 (9to5Mac,
MacRumors, heise, ifun.de) and **no shipped-app story since** — as of July
2026 no consumer app is publicly known to use it (EU's own DMA case-study
factsheet from May 2026 names zero). The hook, phrased carefully:

> "One of the first Wi-Fi Aware apps on the App Store — and the first voice
> intercom built on it."

Outlets covered the promise and have no example to point at. Being the example
is the story. Bonus DE/EU angle: the framework exists partly because of the
DMA; a German indie shipping on it is a tidy narrative for heise/ifun.de.

## Channels (in order)

1. **App Store featuring nomination** (App Store Connect → Featuring
   Nominations) ~3 months pre-launch. Apple's criteria literally include
   "Innovation: new technologies that solve a unique problem", and they
   showcase first-year framework adopters (Liquid Glass gallery precedent).
2. **Apple-ecosystem press:** 9to5Mac "Indie App Spotlight" takes direct
   submissions (michaelb@9to5mac.com); MacStories / AppStories; Launched and
   Under the Radar podcasts for the dev story; **heise + ifun.de** for DACH.
3. **Rider communities, surgically** (answer existing threads, don't blast):
   - ADVRider (350k members): recurring "cheap intercom" threads
   - GL1800Riders (Gold Wing forum — *the* two-up demographic)
   - motor-talk.de "Gegensprechanlage" threads (German)
   - r/motorcycles (1.4M subs; respect the 90/10 rule — one honest
     "I built this" story post)
4. **YouTube gear reviewers** (budget-intercom reviews are an established
   genre): Big Rock Moto (508k), MOTOBOB (400k), The Missenden Flyer (157k,
   mature touring audience), Bennetts BikeSocial. Pitch: "Can two iPhones
   replace a Cardo?" German YouTube is an open gap — affiliate blogs dominate
   there.
5. **Skip Product Hunt.** Evidence: Calimoto got 66 upvotes; Polarsteps 133.
   The proven indie-outdoor template is Slopes (word-of-mouth + App Store
   featuring + seasonal rhythm → $1M ARR solo). Closest moto analog: Scenic —
   a solo dev sustained for a decade on moto-press and community feedback.

## Timing

Riding season is now (July). Sequence:

1. **Immediately:** TestFlight beta recruited from the exact forum threads
   above — testers are riding daily, and battery/range/HFP field data is
   needed anyway.
2. **Early September 2026:** press + paid launch while the season is hot.
   Submit the featuring nomination now to hit this window.
3. **March 2027 (season start):** second, bigger push with the winter's
   polish. Stretch: Android — Wi-Fi Aware is an open standard; cross-platform
   interop would be a genuine moat.

## Pre-launch checklist

- [ ] Trademark clearance (EUIPO/USPTO) on final name; register domains
- [ ] Rename app + bundle display name; new icon text-free (already is)
- [ ] Privacy policy + App Privacy labels ("no data collected" — true)
- [ ] German localization (UI strings + App Store page)
- [ ] Published field numbers: battery %/hr, on-bike range, HFP audio quality
      across a few helmet headsets
- [ ] Session-limit + IAP unlock (StoreKit 2), Family Sharing enabled
- [ ] App Review notes: background audio justification (live intercom)
- [ ] TestFlight public link + a 30-second demo video (two helmets, one take)
- [ ] Featuring nomination submitted in App Store Connect

## Long-shot upside

Cardo acquired the Riser app (2023) to buy a rider audience — hardware
players acquiring rider apps is precedent. Traction here isn't just app
revenue; it's strategic real estate in a space where the incumbents sell
$300+ hardware.

# Instead MVP v0.2

Instead is a phone-first self-improvement feed designed to occupy the same behavioural slot as doom scrolling.

## What changed in v0.2

The feed now learns locally from behaviour.

Done increases the future weight of that category.
Skip gently reduces the future weight of that category.
All preference data stays on-device.
Totals persist between app launches.
Tapping the useful-moments counter opens a session summary.
The seed library has expanded to 21 phone-only activities.

There is deliberately no account, streak, social feed, push notification or backend.

## Core interaction

Swipe up or tap Done.
Swipe left or tap Skip.
Some learning cards have Reveal.

## Test hypothesis

The first test is not whether the app is educational.

The first test is whether, during a real scrolling impulse, opening Instead produces enough novelty and low-effort reward that the user wants another useful card.

## Android build

Every push to `main` triggers a GitHub Actions build. The workflow generates the Android platform project, installs dependencies, builds a debug APK and uploads it as an artifact named `instead-android-apk`.

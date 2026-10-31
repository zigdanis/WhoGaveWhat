# Haptic feedback

Haptics mark a few key moments and nothing else. The app talks to one `HapticsGateway`; the
composition root plays feedback for data results, views play it for taps on their own controls.
`UIKitHapticsGateway` uses UIKit feedback generators so feedback survives a sheet that dismisses
on save, and drops light ticks that follow another haptic within 0.12 s (`HapticThrottle`).

## Where it plays

| Moment | Feedback | Played in |
|--------|----------|-----------|
| Tap the floating Add a gift or Add person button, or the Home welcome card Add a gift button | soft impact (0.5) | `FloatingActionButton`, `WelcomeCard` |
| A gift is saved, create or edit | success | `AppComposition.saveGift` |
| A new person is created (an existing name returns that person and plays nothing) | success | `AppComposition.createPerson` |
| A person is edited and saved | success | `AppComposition.updatePerson` |
| The person editor alert for a duplicate name | warning | `PersonEditorSheet.save()` |
| The person editor alert for any other failure | error | `PersonEditorSheet.save()` |
| `Segmented` changes to a different segment | selection | `Segmented` |
| Insights: a different person picked for Balances for, Person A or Person B | selection | `InsightsView` |
| Insights: swap button | selection | `InsightsView` |

## Silent by design

System toggles (iOS plays its own switch haptic), swipe actions, every delete and confirmation
dialog, the Add Gift From, To, occasion, icon and date picks and quick-date pills, typing, AI icon
and price suggestions arriving, cloud-consent card buttons, the Details disclosure, the Settings
currency list, the Insights year menu, the photo picker, crop and Use photo, tab switches,
navigation, sheet present and dismiss, `onAppear`, `onChange` and reloads, and a failed gift save
(it dismisses without a visible message, so a buzz would be unexplained).

## Rules

- One haptic per deliberate action.
- Never on programmatic changes, initial values or keystrokes.
- Never stack on a haptic iOS already plays.
- Warning and error only alongside a visible message.
- Light ticks are throttled; a dropped request is not queued.

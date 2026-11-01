# App Store rating prompt

The app asks for a rating only through the system sheet (`requestReview`). App Review Guideline 5.6.1
forbids custom review prompts, and asking "Do you like the app?" first to send only happy users to the
App Store is review filtering, so there is no pre-prompt and no "5 stars" wording anywhere. The odds of a
good rating come from the moment instead.

## When the app asks

All of these must hold, checked when a **new** gift is saved (edits don't count):

- the app has been in the foreground on at least **3 distinct calendar days** (day 1 is the first launch
  of a build with this feature, also for people who installed earlier);
- at least **5 gifts** and **2 people** are stored;
- no gift save failed and no gift or person was deleted since the app last came to the foreground;
- no request was made yet this session or for this app version;
- after an earlier request: at least **120 days** have passed, fewer than 3 requests were made in the last
  365 days, and the user has since saved **3 new gifts** on **2 new days**.

The request comes **2 seconds** after the gift sheet closes, so the saved gift shows on Home first. If by
then the user has left Home (other tabs own the Add person, Rename and Insights sheets), opened the gift
sheet again, or the app is no longer active (Control Center, a notification, the app switcher), the moment
is skipped and a later new gift can try again.

The rules live in `ReviewPromptPolicy` (`WhoGaveWhat/Models/ReviewPrompt.swift`); their state is stored
in `UserDefaults` under `reviewPrompt`.

## What iOS does with it

iOS shows the sheet at most three times in 365 days per device and decides on its own whether to show it.
It never appears in TestFlight builds and always appears in Debug builds. The app can't tell whether the
sheet appeared or how the user rated; `review_prompt_requested` in [analytics](analytics.md) counts the
requests, and App Store Connect shows the ratings per version.

## Checking it

Verification launches (`KS_` variables) never ask, except `KS_REVIEW_PROMPT=ready`: it starts the launch on
the third day of use, so saving a new gift, with at least 5 gifts in total, shows the sheet in development
builds (run from Xcode or installed on a Simulator).

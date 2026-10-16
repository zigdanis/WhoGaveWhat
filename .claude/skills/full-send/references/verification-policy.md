# Efficient verification, failures and waiting

## Batch before CI

- **Prepare:** collect known fixes and review findings, fetch `origin/master`, integrate it and run relevant local checks before pushing, so CI validates the combined result.
- **Reuse:** use the automatic run from that push. Don't start duplicate runs or rerun successful checks for an unchanged commit. Superseded runs are cancelled automatically.
- **Repeat only when needed:** meaningful changes, base synchronization or a diagnosed failure can require another run. Within an authorized delivery, proceed without asking for separate permission for each necessary run; respect any explicit user budget.
- **Track:** keep run links and results with the task, including retries and cancellations.
- **Diagnose:** if the same failure repeats, investigate before another attempt. Stop retrying blindly; explain the blocker and ask for input only when no concrete correction is available or continuing would materially expand cost or scope.

## Classify before correcting

- **App bug:** the app behaves or looks wrong. Fix it.
- **Test bug:** the test does not match expected behavior. Fix the test.
- **CI/OS problem:** CI, the Simulator or an OS service failed (for example, the Simulator Spotlight catalog). Don't chase it with app changes; move that check to an optional diagnostic or a post-release device check and report it.
- **Missing evidence / pending review:** required media or review is not ready yet. This is not a code failure; don't push a change for it.

## Reviews

- **Independent review** is required for every change and every follow-up fix.
- **Bots:** validate CodeRabbit and Macroscope findings before changing code. Fix real ones; reply with evidence to the rest. A rate-limited, skipped or still-running bot review is not a merge blocker once independent review is clean and no actionable comment is open. Don't wait an hour for a bot quota.

## Waiting

- **PRs:** call `watch_pull_request` and end the turn; T3 Code wakes the thread on failures, passing checks, new comments and conflicts. A wake is news, not a merge decision: recheck the head before merging.
- **Apple:** processing and beta review are normal waiting states.
- **Blocked:** say what is done, what is pending and what can unblock the task.

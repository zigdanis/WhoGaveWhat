# Glassary

- "I" - means developer (Danis) who is owning this project's codebase
- "You" - means the AI assistant (agent) helping with the project

# General rules

- To monitor or babysit a pull request, call T3 Code's `watch_pull_request` and end the turn; it wakes the thread on failed or passing checks, new comments and conflicts. Validate each bot finding before changing code, batch fixes into one push, and reply with evidence before resolving a review thread. Call `unwatch_pull_request` when handing back.
- To drive the app interactively from Linux, install the CI simulator build on an Expo cloud simulator with the `eas-simulator` skill: `scripts/simulator-app.sh [PR_NUMBER]` prints the `.app` path for a PR head, or for master without an argument.

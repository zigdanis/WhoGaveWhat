# Glassary

- "I" - means developer (Danis) who is owning this project's codebase
- "You" - means the AI assistant (agent) helping with the project

# General rules

- To monitor or babysit a pull request, call T3 Code's `watch_pull_request` and end the turn; it wakes the thread on failed or passing checks, new comments and conflicts. Validate each bot finding before changing code, batch fixes into one push, and reply with evidence before resolving a review thread. Call `unwatch_pull_request` when handing back.

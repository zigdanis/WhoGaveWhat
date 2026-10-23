# WhoGaveWhat release lanes

Use `python3 scripts/testflight.py` for manual commands from Linux/T3.
These lanes run inside the protected manual workflow; local `beta`, ad hoc project version bumps and tag pushes are
no longer supported.

| Lane | Operation |
| --- | --- |
| `ios release_preflight` | Validate Apple access, tester/group and app signing; no upload |
| `ios app_store` | Archive/upload a new receipt or resume its exact build |
| `ios release_status` | Read recorded Apple build, distribution and locale state |
| `ios release_notes` | Update/read back EN/RU notes on the existing processed build |
| `ios store_metadata` | Upload `fastlane/metadata` (and `STORE_SCREENSHOTS_DIR` when set) to the `STORE_VERSION` App Store version; no build, no review submission |

`store_metadata` runs in the manual `App Store metadata` workflow. App Review contact details come from the
`BETA_REVIEW_INFO` secret, never from the repository; only `metadata/review_information/notes.txt` is committed.

Native tests and app smoke use direct Apple tools through
`scripts/run-app-smoke.py`, locally on macOS or in the `Tests` workflow.
Run release helper tests with one Ruby process per file:

```sh
for test in fastlane/tests/test_*.rb; do
  bundle exec ruby "$test"
done
```
 Release archive/export requires the explicit bounded
exception documented in the operations guide.

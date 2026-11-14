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
`BETA_REVIEW_INFO` secret when it holds all four contact fields. With no contact field the upload leaves the
App Review section (contact and notes) as entered in App Store Connect; with only some of them it fails. They never come from the repository; only `metadata/review_information/notes.txt` is committed.

## Credentials

The lanes read their credentials only from the `testflight` environment secrets in GitHub; nothing
is needed on a developer machine. Owner copies live in Danis's SOPS vault (`~/myai/fleet-secrets`,
opened by MacPro, MacAir and Raspi), with no plaintext files on any machine since 2026-11-15:

| Vault file | Contents |
| --- | --- |
| `whogavewhat/asc-api-key.json` | App Store Connect Admin API key `fastlane`, fastlane JSON layout (`key_id`, `issuer_id`, `key`) |
| `whogavewhat/match-password` | Match passphrase for `zigdanis/zigdanis-certificates`, branch `whogavewhat-ci` |
| `whogavewhat/fastlane.env` | Former local `fastlane/.env`: Apple ID, beta feedback e-mail, ASC key/issuer IDs, `MATCH_GIT_URL` |

The repository's Match deploy key (`MATCH_GIT_PRIVATE_KEY`) exists only as a GitHub secret. A
read-only check of the Apple key without Fastlane:

```sh
cd ~/myai/fleet-secrets
sops exec-file --no-fifo whogavewhat/asc-api-key.json \
  'python3 ~/myai/fleet/skills/app-store-connect-api/scripts/asc.py --credentials {} apps'
```

Native unit tests use direct Apple tools through
`scripts/run-unit-tests.py`, locally on macOS or in the `Tests` workflow.
Run release helper tests with one Ruby process per file:

```sh
for test in fastlane/tests/test_*.rb; do
  bundle exec ruby "$test"
done
```
 Release archive/export requires the explicit bounded
exception documented in the operations guide.

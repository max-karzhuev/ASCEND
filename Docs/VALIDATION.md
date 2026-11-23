# Validation results

## Mental math and release readiness, 23 November 2026

Version 1.7 (build 9) passed the universal Mac Release and iPhone Simulator builds from a clean Git checkout. Regenerating the Xcode project produced no diff. All 41 Swift core tests and 21 gateway tests passed. The five new tests cover direct and inverse operations, operand bounds, invalid settings, partial answers, zero, replay, and the exact scoring deadline.

A native Mac UI harness rendered both dashboard widths using synthetic data and opened the production drill view. The answer field took keyboard focus. Typing the first digit of 13 kept the problem in place. Completing the number cleared the field. A second answer advanced immediately using the same field. When five seconds elapsed, the device metadata contained the selected settings and a two-point score. iPhone Simulator verification covered compilation. The narrow layout render used the Mac SwiftUI host.

The release-tag CI command passed locally for `v1.7` and rejected a deliberately mismatched tag. The app and embedded widget versions matched. Strict signature verification passed for the packaged app and a fresh extraction of its ZIP. The Mac binary includes arm64 and x86_64. Publication, a hosted Actions run and public notarization remain pending.

## Puzzle dashboard and release handoff, 23 November 2026

Version 1.6, build 8, passed a fresh-checkout build for universal macOS Release and iPhone Simulator. Project regeneration produced no diff. All 36 Swift core tests and 21 gateway tests passed. The packaged app, embedded widget extension, and a fresh extraction of the Mac ZIP passed strict signature verification.

An isolated in-memory profile opened a built-in collection, recorded a locally graded answer and round-tripped the archive. A local authenticated gateway fixture exercised the app’s topic loader and session client with three generated-format physics questions. Concurrent requests for the same topic and a second load after saving used exactly one upstream request. The fixture used a test token and simulated provider responses. The app’s actual SwiftUI dashboard rendered at 1000- and 390-point widths, with offline puzzles and a connected sample conversation composer. The narrow render used the Mac SwiftUI host. The iPhone simulator target was compiled separately.

The GitHub workflow now includes the core and gateway suites, generated project consistency, native builds and Mac signature verification. Equivalent commands ran locally. A hosted GitHub Actions run, physical iPhone signing, live paid-provider credentials and public Mac notarization remain outside these checks. The source inventory excludes personal databases, local download bundles and gateway environment files. A local history scan found no matches for the common provider-token and private-key signatures checked.

## Widget appearance and AI Chat, 23 November 2026

ASCEND 1.5 built for universal macOS Release and the iPhone simulator. All 34 Swift core tests and 21 gateway tests passed. A local chat fixture exercised ten consecutive turns, the recent-context limit, a failed send and retry, cancellation, and clearing while a reply was pending. The authenticated gateway tests verified that the selected model received the ordered conversation and that invalid conversations and malformed replies produced errors. Provider responses were simulated.

SwiftUI rendered the task list and monthly calendar with synthetic data in full-color, accented, and vibrant rendering environments. The accented render preserved pink tiles, contrasting date labels, and graded glow. The vibrant render showed distinct brightness levels. Desktop compositing and WidgetKit refresh latency on a user's wallpaper need a check on that desktop. Strict signature verification passed on the Mac app and on a fresh extraction from the ZIP.

## Quest deletion and calendars, 23 November 2026

ASCEND 1.4 passed the universal macOS Release and iPhone Simulator builds. All 34 core tests passed. The new regression cases cover removing an occurrence without removing the routine, removing a completed parent along with its linked credit, stale offline replay, export/import validation and removing one weekly session while preserving the others.

A disposable iPhone simulator ran the app’s calendar reader against real EventKit calendars populated with synthetic assignments and exams. It verified opt-in selection, exclusion of an unselected calendar, the 30-day window, all-day events, chronological order, selection persistence, removal of an upstream event and disconnection. No personal Google account, school Canvas subscription or live iCloud exchange was used. The Mac bundle passed strict code-signature verification.

## Task and calendar widgets, 22 November 2026

Version 1.3 passed the Mac Release and iPhone Simulator builds. Both new SwiftUI widget views were rendered with sample data. PlugInKit registered the packaged 1.3 widget extension. The launched app published a task list and month summary with consistent counts and intensity values. Desktop placement and actual WidgetKit refresh latency were not manually tested.

## Square dates, 22 November 2026

Version 1.2.1 passed macOS Release and iPhone Simulator builds. SwiftUI rendered the production date tile at 28 × 28, 35 × 35, and 44 × 44 points.

## Calendar glow, 22 November 2026

Version 1.2 passed the macOS Release and iPhone Simulator builds and all 31 core tests. A 12-quest regression test checks each completion fraction in both directions and the future-day guard. A SwiftUI render of the Baby Blue tile showed increasing measured brightness across all 13 states from zero to twelve completions. Reduced Motion uses immediate updates.

## Desktop widget and colors, 22 November 2026

ASCEND 1.1 built successfully as a Mac Release app with its WidgetKit extension and as a separate iPhone simulator app. All 30 domain tests passed. Strict recursive code-signature verification succeeded for the delivered Mac bundle and its embedded extension. After launching the delivered app, macOS PlugInKit listed `com.example.ascend.widget(1.1)` at the delivered path. The app wrote its minimal local widget summary with the seven expected fields. Desktop placement, rendering in both sizes, WidgetKit refresh latency, and the signed Cloud App Group were not manually verified. The existing gateway implementation was unchanged.

## Original release, 21 November 2026

Completed on **21 November 2026**, using Xcode 27.2 (27B52), Swift 6.4.2, macOS/iOS 27.2 SDKs, and Node 26.13.0. Deployment targets remain macOS 14 and iOS 17. Results below describe actual checks, not inferred production readiness.

## Automated checks

| Check | Result |
| --- | --- |
| `swift test` | **30 tests passed, 0 failures** |
| Gateway `npm test` / `node --test` | **19 tests passed, 0 failures** |
| macOS Release, generic macOS destination | **BUILD SUCCEEDED**, universal arm64 + x86_64 |
| iOS Debug, generic iOS Simulator destination | **BUILD SUCCEEDED** |
| Packaged Mac app `codesign --verify --deep --strict` | Valid on disk; satisfies designated requirement |
| Standalone Release launch | Opened successfully from the delivered app bundle |

Builds produced no compiler errors. Xcode emitted its non-blocking “Metadata extraction skipped, no AppIntents.framework dependency found” warning; this app does not implement App Intents. Earlier macOS Debug and iOS Simulator builds also succeeded. The final tests and build-result extracts are in [Validation](Validation/).

Core coverage includes spring/fall DST, shared timezone boundaries and transitions, selected weekdays, stable daily identities, explicit weekly sessions, frozen history, future revision field merging, duplicate completion, exact undo, reward snapshots, linked-goal reversal, milestone weights, calendar denominators, rest-day streaks, XP/ranks, per-field merging, deterministic conflict ordering, stale drafts after submission, sticky deletion, shared reset, archive validation/round trips, and deterministic question grading. Merge checks use shuffled arrival order and repeated operations.

Gateway tests use local HTTP fixtures and mocked upstream transports. They cover authentication, request/output schemas, model allowlists, all four distinct adapter formats, incomplete/refused responses, retries, cancellation including stalled DNS, private-address rejection, quota persistence, malformed output, request size, completed-request caching, and in-flight duplicate rejection. **No test made a live provider call.**

## Manual Mac checks

All test progress was entered through the UI in the explicitly labeled `--validation` workspace. The personal workspace was left at onboarding with no test quests or XP.

- Created a recurring quest, completed it for 25 XP, undid it to 0 XP, and restored completion. Today’s count, calendar brightness, and streak changed with the action.
- Created a numeric goal for 10 chapters and linked a quest contributing one chapter. Completion changed the goal to 10%; undo returned it to 0%; restore returned it to 10%, with one corresponding XP reward.
- Quit and relaunched the app; quest states, 50 total test XP, the linked goal’s 10% progress, and the chosen Crimson theme persisted. Verified this again in the packaged Release build.
- Selected Shadow, Amber, Emerald, and Crimson and observed theme changes. The selected theme survived restart.
- Used the app with iCloud and AI unconfigured; quest/goal tracking remained available, cloud status said local mode, and Brainmaxing offered setup instead of fabricated content.
- Resized the Mac window through the system’s half-screen layout. The dashboard changed from two columns to one, retained readable cards, and scrolled to quests, goals, Brainmaxing, and status. Restored the previous window size afterward.
- Opened the packaged app normally and confirmed clean personal onboarding, independent of Xcode.

These checks establish operation without configured network services. They do not claim that the Mac’s network adapter was physically disabled during testing.

## Manual iPhone Simulator checks

Used the installed iOS 27.2 runtime and iPhone 17e simulator in Xcode Device Hub, with a separate validation workspace.

- Completed onboarding and created “Read on iPhone.”
- Completed the daily quest and observed 25 XP, 1/1 planned quests, the highlighted date, and a one-day streak.
- Installed the final build over the existing installation and relaunched. The same history and 25 XP remained.
- Opened the selected calendar day. It showed 1/1, 100%, and 25 XP. Undo changed those to 0/1, 0%, and 0 XP; restore returned exactly the original reward.
- Inspected the narrow vertical dashboard, player card, calendar, native five-tab navigation, dated detail sheet, and Brainmaxing setup state. Fixed a validation-only banner overlap and verified the final layout.

This is simulator validation, not a physical-device installation or a complete VoiceOver/Dynamic Type audit. Large text has an alternate calendar list in code; the full accessibility-size matrix remains to be checked on devices.

## External setup and unverified checks

- **Live CloudKit and two-device convergence:** requires a signed build on both platforms, one real private container/environment, and the same Apple Account. The merge algorithm is tested; the live service exchange, account switching, schema deployment, and two-device checklist below have not been executed.
- **Live Brainmaxing generation/grading:** requires a deployed reachable gateway and enabled API credentials/models. All four adapters are implemented and fixture-tested against documented formats, but provider acceptance, billing, latency, and live feedback quality remain unverified.
- **Physical iPhone install:** requires the user’s team/provisioning and device trust/Developer Mode. No signed IPA is included.
- **Notification delivery:** scheduling and permission flows are implemented; real notification delivery under Focus, backgrounding, and device handoff has not been manually verified.
- **Distribution:** the Mac app is locally ad-hoc signed, not notarized or submitted to an app store. No paid infrastructure or public deployment was created. The supplied Docker deployment instructions were not exercised.
- **Data lifecycle:** the operation log is append-only. Shared reset is a logical reset with stale-device protection, not physical erasure. Follow [DATA.md](DATA.md) for account changes, backups, and Apple’s storage controls.

## Two-device checklist after configuration

Use two test installations with the same Apple Account, CloudKit container, and environment. Export any valuable history first. Confirm the exchange state on both devices after each step; uploading from one device does not prove receipt by the other.

1. Create a recurring quest on Mac, exchange on both, complete on iPhone, then exchange and compare XP, goal quantity, calendar, and streak on Mac.
2. Undo on Mac; exchange and verify the same reversal on iPhone. Restore once and verify one reward.
3. With both devices disconnected, complete the same previously shared occurrence on each. Reconnect/exchange and verify one reward/contribution.
4. Complete different occurrences offline. Reconnect and verify that both survive.
5. Make independent field edits and conflicting edits offline. Exchange twice and verify both devices converge according to the documented rules, including future routine revisions.
6. Archive or reset while the other device is offline. Reconnect the stale device and verify old active records do not reappear.
7. Restart both apps, exchange, and compare the derived progress and pending/error status.
8. Generate a learning session with configured AI, cache it on both devices, submit an answer, and verify synchronized history and non-duplicated XP. Test a saved answer awaiting online grading.
9. Exercise sign-out and account mismatch using disposable test data. Verify that the app pauses rather than transferring history to a different account.
10. Enable reminders on only one selected device and verify delivery, cancellation after completion, and handoff behavior after both devices reconnect.

# ASCEND project handoff

ASCEND 1.6 (build 8) is a local-first SwiftUI app for macOS 14+ and iOS 17+. The repository contains the native app, Mac widget extension, dependency-free Swift core, and optional personal Node gateway. The app opens in local mode. Signing for a physical iPhone, private iCloud sync, and public Mac distribution each have their own setup in the [installation guide](Docs/SETUP.md).

## Run a fresh checkout

Open `ASCEND.xcodeproj`, choose the **ASCEND** scheme and **My Mac**, then run. The local Mac and simulator builds require Xcode with the macOS 15+ SDK for the widget image APIs and the iOS 17+ SDK. Use Node 22+ for the gateway. The local build does not require a development team or provider key.

```sh
swift test
(cd Gateway && node --test)
./Scripts/build-local.sh
open build/mac/Build/Products/Release/ASCEND.app
```

For iPhone Simulator, select an installed iPhone simulator in Xcode or use the simulator build command in the [README](README.md). Run `python3 Scripts/generate_project.py` after adding Swift source files, and commit the generated project. The generator owns build settings and target membership. Apply project-wide configuration changes there too.

## Where to make changes

| Area | Entry point and behavior |
| --- | --- |
| Home and navigation | `App/Overview.swift` lays out the calendar, player progress, quests, goals, puzzle feed and chat. Wide windows have two columns. `App/ASCENDApp.swift` owns routes, environment objects and widget deep links. |
| Puzzle content | `Sources/AscendCore/HomePuzzles.swift` defines four offline collections and the topic-generation configuration. Keep published question and collection IDs stable so existing attempts still match. |
| Puzzle feed | `App/PuzzleFeed.swift` selects a Brainmaxing subject, requests three practice questions through the existing session endpoint, and saves the result as a learning session. The default subject rotates with the planning date. The topic menu offers each selected subject and General. |
| Play and grading | Opening a feed row selects that question in `App/Brain.swift`. General questions have local answer keys and worked explanations. The session view handles drafts, hints, submission and practice XP. Existing Brainmaxing sessions decode without the optional home-feed marker. |
| AI and chat | The embedded and expanded chat share `ChatSession` in `App/Chat.swift`. `App/AIClient.swift` handles the selected model, Keychain token, gateway limits and networking. `Gateway/server.mjs`, `schema.mjs` and `providers.mjs` handle authentication, validation and provider requests. |
| Persistence and synchronization | `App/AppStore.swift` persists the change ledger in SwiftData. `Sources/AscendCore/ChangeLog.swift` merges changes and validates archives. Cloud-enabled builds can exchange them with private CloudKit. See [data ownership](Docs/DATA.md) and [architecture](Docs/ARCHITECTURE.md). |
| Widgets and calendars | `App/PublishWidget.swift` writes a minimal desktop summary. `Widget/` renders the three Mac widgets. `App/CalendarAgenda.swift` reads selected EventKit calendars, including Google accounts and Canvas calendar subscriptions available to the system Calendar app. |

## Puzzle requests and storage

Connecting a model enables a daily set for the active subject. Opening or choosing a topic can use one generation request. The loader reuses a saved set for the same planning day, subject, provider and model. Overlapping requests from the same store share an in-flight check. Each device can generate its own set before CloudKit exchanges complete. General puzzles run offline. When generation fails, the feed offers retry and keeps a saved set or the general collection playable.

The gateway receives the chosen subject and learning settings. Generated questions, worked solutions and submitted attempts enter the same local history, export and optional private sync as other Brainmaxing sessions. Chat uses a separate in-memory conversation. The provider keys belong on the gateway. The native app stores only the gateway token in Keychain. For deployment, configuration and usage controls, see the [gateway guide](Gateway/README.md).

## GitHub and distribution

- The workflow in `.github/workflows/test.yml` runs on pushes and pull requests. It checks project regeneration, runs the Swift and Node suites, compiles the Mac app with its widgets, verifies the bundle signature, and compiles the iPhone simulator app. It uses read-only repository permissions.
- Local copies of the runnable app and the two ZIP files live in the ignored `Downloads/` directory of the delivery repository. A fresh checkout builds its own app. Use a tagged source archive for source distribution.
- The local Mac package is ad hoc signed. For a public Mac download, sign the app and extension with the project's Developer ID identity, notarize and staple the app, then verify the extracted release ZIP on a separate Mac. Attach that ZIP to the GitHub Release for the matching source tag.
- The repository owner still needs to choose the GitHub destination and visibility. If releasing under an open-source license, choose the intended license before inviting reuse. The repository currently contains no license grant.
- For App Store or iCloud distribution, configure the owner's bundle identifiers, team, App Group and CloudKit container, then verify physical-device signing and production sync. Replace the example identifiers in the project generator and configuration as described in the installation guide.

## Verification

See [validation results](Docs/VALIDATION.md) for build and test evidence and the scope of live checks. For a quick manual pass, open General, choose the second question, request a hint, submit an answer and revisit it from Brainmaxing. With a configured gateway, select a custom subject, reopen Home and verify the same set returns. Send a draft from the home chat and open the expanded conversation. Check the compact and full calendars after completing a scheduled quest.

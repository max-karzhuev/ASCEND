# Build, sign, and install

## Run on this Mac now

The delivered `ASCEND.app` is a universal, locally signed Mac app built from this source. Double-click it. To keep it installed, copy it into your Applications folder using Finder. The app keeps its database in its sandbox’s Application Support/ASCEND directory and continues to work with Codex, Xcode, and Terminal closed.

The included local build does not have an iCloud container configured. It tracks quests/goals offline immediately. It is not notarized for distribution to other people. If macOS blocks a copied build, use Xcode to build and run the source with your own signing identity; do not disable system security globally.

## Add the Mac widget

Open ASCEND once. Control-click the desktop, choose **Edit Widgets**, search for **ASCEND**, and add **Tasks to Complete**, **Calendar Glow**, or **Today’s Progress**. Click **Done**. Clicking the task list opens Quests. Clicking the calendar opens Overview. The small and medium task lists show up to three titles, and the large list shows up to eight. A remaining count identifies additional tasks. Placement and refresh timing are managed by macOS. See [Apple’s widget guide](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac).

The widget uses the same theme and progression rules as the app. The app publishes a summary when history or the theme changes. If a new planning day starts while ASCEND is closed, the widget prompts you to open the app to refresh the daily plan. macOS controls the desktop tint. For persistent full color, choose **System Settings → Desktop & Dock → Widgets → Dim widgets on desktop → Never**.

## Build from source

1. Install/open Xcode, review its license, and let platform components finish installing. This delivery was built using Xcode 27.2 and SDK 27.2; the app targets macOS 14 and iOS 17 or later.
2. Open `ASCEND.xcodeproj`.
3. Select scheme **ASCEND** and destination **My Mac**. This scheme uses `Configuration/Local.entitlements` and an empty CloudKit container identifier.
4. Press Run. ⌘N creates a quest. ⇧⌘R requests a cloud exchange when enabled.

For a standalone Release build, run `./Scripts/build-local.sh`; its final output gives the app path. Build products are not your database. Rebuilding or moving the app does not erase stored history.

## Install on iPhone

1. In Xcode → Settings → Accounts, add your Apple developer account yourself.
2. Select the ASCEND target → Signing & Capabilities, select your team, and set the project build setting `ASCEND_BASE_IDENTIFIER` to a unique bundle identifier you own. Use the same identifier/team for both platforms.
3. Pair your iPhone with the Mac. In Xcode 27, open **Xcode → Open Developer Tool → Device Hub**; older Xcode versions use Devices and Simulators/Simulator.
4. Complete the phone’s trust and Developer Mode prompts yourself. Apple documents the flow in [Enabling Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
5. Select your phone as the destination and Run the ASCEND scheme.
6. After installation, open ASCEND from the phone’s Home Screen. Xcode, Codex, and the Mac need not remain open for local tracking. Development provisioning must remain valid; renewal/distribution depends on your Apple account and signing method.

No signed physical-device IPA is included because your team, certificate, and provisioning profile were not supplied. Nothing was submitted to App Store Connect or TestFlight.

## Enable one shared iCloud history

Use a developer team entitled to CloudKit. Keep a JSON export before changing bundle IDs, containers, or environments.

1. Use your final bundle identifier and select the same team for Mac and iOS.
2. Select scheme **ASCEND-Cloud**. It uses CloudDebug for running and CloudRelease for archiving.
3. In the target’s build settings, replace `ASCEND_CLOUD_CONTAINER = iCloud.com.example.ascend` with your real container identifier in both cloud configurations.
4. In Signing & Capabilities, enable iCloud → CloudKit and associate that same container. Preserve the platform-specific entitlements. The Mac Cloud configuration uses `CloudMac.entitlements`, and the iOS Cloud configuration uses `Cloud.entitlements`. For the Mac Cloud build, select the same signing team for ASCEND and ASCENDWidget and register the same App Group from `ASCEND_WIDGET_GROUP` for both targets.
5. CloudDebug uses `ASCEND_CLOUD_ENVIRONMENT = Development`. CloudRelease uses Production. **Both devices must use the same environment.** Development records do not automatically become production records.
6. Build and run a CloudDebug app on both devices, signed into the same Apple Account with iCloud available.
7. In ASCEND Settings, choose **Enable private iCloud sync** and review the local-history merge explanation. Enable on the second device too.
8. The app creates private zone `ASCENDHistory` and record type `AscendOperation` with one Bytes field, `payload`. If your development schema is restricted, create that record type/field in CloudKit Console. No custom query indexes are required.
9. Once the development schema is validated, deploy its schema to Production before using CloudRelease. Schema deployment copies definitions, not records. See Apple’s [schema deployment guide](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
10. Complete the two-device checklist in `VALIDATION.md`. Do not infer sync success merely from a local save or successful upload.

The app uses **explicit CloudKit synchronization only**. Do not change the SwiftData model configuration to automatic CloudKit sync; that would introduce a competing mechanism.

## Local-to-cloud and account changes

Enabling sync merges existing local operations into the current Apple Account’s private container after fetching its history. Existing logical IDs deduplicate; unrelated locally created quests remain separate. This first connection binds the local store to that account.

If you sign out, local tracking continues. Reconnect the original account to resume. If another account is detected, syncing pauses and refuses to mix histories. To start fresh with the new account, export any needed data, clear local history through Settings, then connect. Importing an old export into a new account is an explicit data-transfer decision.

## School and personal calendars

On each device, open **ASCEND → Settings → Connected calendars → Connect Apple Calendar**. Apple requires full calendar permission to read events. Choose the calendars to display. Home shows up to three upcoming events. **Quests → Upcoming** shows the next 30 days and includes a refresh button.

- **Canvas LMS.** Open your school’s Canvas **Calendar → Calendar Feed** and copy the private subscription URL. On Mac, paste it into **Apple Calendar → File → New Calendar Subscription**. On iPhone, use **Calendar → Calendars → Add Calendar → Add Subscription Calendar**. Refresh ASCEND’s calendar list and enable the subscription. Published assignments, quizzes, and exams appear when Canvas includes their dates in that feed. The refresh interval depends on Canvas and the system calendar subscription. [Canvas feed instructions](https://community.instructure.com/en/instructure/kb/articles/662804-how-do-i-view-the-calendar-ical-feed-to-import-and-subscribe-to-an-external-calendar) · [Apple subscription guide](https://support.apple.com/guide/calendar/subscribe-to-calendars-icl1022/mac)
- **Google Calendar.** Enable Calendars for your Google account in the device’s Calendar accounts. On Mac you can use **Calendar → Add Account → Google**. Sign in through the system and then select the relevant calendars in ASCEND. [Google’s Apple Calendar setup](https://support.google.com/calendar/answer/99358)
- **Apple Calendar.** Select the iCloud or local calendars you want to see under Connected calendars. To stop displaying events, deselect those calendars or choose **Disconnect all**. To revoke system access, use **Privacy & Security → Calendars**.

This integration reads dates and titles through EventKit. Calendar events stay separate from quest progress. ASCEND keeps the selected calendar identifiers in device preferences and the displayed agenda in memory. Calendar accounts and private subscription URLs are managed by the system Calendar app.

## AI and notifications

Core tracking never requires the gateway. Follow `Gateway/README.md` to enable AI Chat and generated learning sessions. If your gateway predates ASCEND 1.5, update its code or container and restart it with the same environment and quota storage. Open **AI Chat** from the Mac sidebar or the speech bubbles in the iPhone navigation bar. In the app, use the gateway token, **not a provider API key**.

Enable reminders inside ASCEND to trigger Apple’s notification permission request. Only the selected delivery device schedules notifications. Task times, the 8 PM check-in, and the 6 PM Brainmaxing reminder use the shared planning timezone. The app schedules up to seven days ahead, capped at 60 pending requests. Open it periodically to refresh the queue. Focus, notification permissions, and OS delivery decisions still apply.

## Validation workspace

To test without populating personal history, launch the Mac app with:

```sh
open -n /absolute/path/to/ASCEND.app --args --validation
```

This displays a validation label and uses Application Support/ASCEND-Validation. Normal launches use Application Support/ASCEND. No fixtures are seeded into either store. Simulator installations are separate device sandboxes. Do not enable iCloud for a validation workspace against a real personal container.

## Apple Health and Apple Watch

Use the Apple Health widget in ASCEND on iPhone (or supported iPad). Choose **Connect Apple Health** and allow the data types you want to display. Apple Watch and other Health-compatible trackers must first sync with Apple's Health app. ASCEND reads steps, sleep, active energy and walking/running distance; it does not pair with a Watch directly or write Health records. Manage permissions in Health → profile → Apps → ASCEND. A dash may mean no samples or denied read access. Mac displays connection guidance instead of health readings.

The local and Cloud iOS entitlement files contain `com.apple.developer.healthkit`, and Info.plist includes `NSHealthShareUsageDescription`. For a physical iPhone, enable HealthKit for your registered bundle identifier/team and regenerate the provisioning profile as needed. macOS uses separate entitlements without HealthKit. Live Health/Watch data and notification delivery need testing on an authorized physical device.

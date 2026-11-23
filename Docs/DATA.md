# Data ownership, backups, and deletion

## Where your information lives

On the Mac, choose **Settings → Your data → Show database in Finder**. The delivered build stores your history at `~/Library/Containers/com.example.ascend/Data/Library/Application Support/ASCEND/history.store`, with SQLite sidecar files managed by SwiftData. On iPhone the equivalent file lives in ASCEND’s private app container. Use **Export JSON** for a portable backup.

The local Mac build saves a separate widget summary at `~/Library/Application Support/ASCEND Desktop Widget/desktop-summary.json`. It contains the theme, level, progress toward the next level, up to eight unfinished quest titles, the total remaining count, monthly date/quest counts and intensities, and the day’s expiry. The widget reads only this summary. A team-signed Cloud build uses its shared App Group for the same file. Validation sessions never publish into the personal widget.

Local mode keeps tracking on the device. Enabling sync in a configured Cloud build sends the history to your private Apple CloudKit database. Brainmaxing sends session requests and individual answers needing online grading through your configured gateway to the chosen AI provider. The app stores the gateway token in the device Keychain.

## Deleting a quest

Use the quest’s **…** menu to delete a single occurrence or the entire routine. One-time quests have a **Delete quest** action. The trash button under **Quests → Routines** also works for archived templates. Weekly targets offer deletion in their History menu. Review the scope in the confirmation dialog.

Deletion removes the affected items, XP, linked goal credit, and planned-day counts from the active history. A deleted occurrence is skipped during later scheduling. A deleted parent also hides completions and occurrences arriving later from an offline device. The existing append-only operation archive retains historical payloads and deletion markers. Archive a routine instead if you want to keep historical scores.

## Export and import

Settings → Export JSON writes a version-1 archive of the operation history, including quests, snapshots, goal contributions, completed/undone rewards, preferences, learning sessions, answers, and reports. It also retains previous generations after a shared reset. Store it privately if your notes or learning answers are sensitive.

Gateway tokens, provider credentials, Apple Account identifiers, CloudKit cursors, and per-device reminder/network metadata are not exported. Tokens stay in the device Keychain; upstream API keys stay on the gateway server.

Import validates the entire merged graph before saving it. Unsupported versions, malformed/oversized data, missing relationships, impossible values, and two different payloads with the same immutable operation ID are rejected. Reimporting the same archive does not duplicate progress. A reset operation in an imported archive participates in the same generation rules as synced resets; inspect the source of an archive before importing it.

## Archive, undo, reset, and clear are different

| Action | Effect |
| --- | --- |
| Undo a quest | Reverses that logical completion’s XP and linked contribution once. The completion record remains. Re-completing restores its original reward snapshot. |
| Archive a routine or goal | Preserves recorded history. Routines stop future planning at their next effective boundary. Archived items can be restored. |
| Remove a manual contribution | Adds a permanent tombstone for that contribution ID. Its value no longer counts. The old operation remains in the audit archive. |
| Clear local data | Removes this device’s history and pending work and disables cloud sync. Cloud records are unchanged. Reconnecting can download them again. Export unsynced changes first. |
| Reset shared history | Creates a new history generation. Connected devices adopt it during later exchanges; stale old-generation changes cannot revive the prior history. The underlying operation archive is retained. |
| Forget gateway token | Removes the token for the current gateway URL from this device’s Keychain. It does not delete learning history. |

Shared reset and clear-local actions have explicit confirmation dialogs. A local-only shared reset affects this local history; if it is later uploaded, its generation marker participates in cloud reconciliation.

## Physical erasure

The in-app shared reset is a **logical reset, not physical erasure of historical payloads**. Retaining operation identities/tombstones prevents offline devices from reviving deleted history. This release deliberately has no unsafe automatic log-compaction or cloud-zone recreation flow.

For physical erasure:

1. Pause sync on every device and keep them paused. Export only if you want a private backup.
2. Clear local data on each device in ASCEND Settings. Delete any exports/backups you no longer want through their normal file-management controls.
3. Remove ASCEND’s cloud data using the Apple Account’s iCloud storage controls or the private database’s CloudKit Console controls for your development container. Review Apple’s deletion confirmations yourself. Do not reset a shared development environment containing unrelated users’ data.
4. Do not reconnect an uncleared old device. Clear it before reconnecting. When a previously bound app observes an externally removed cloud zone/record, it pauses rather than recreating its stale data.
5. Forget the gateway token on each device if desired. Revoke/rotate it on the server to invalidate retained copies. Remove server-side provider credentials if you are decommissioning the gateway.

SQLite/WAL files, system backups, iCloud retention, and device storage disposal are governed by the relevant operating system/service. The app does not claim forensic secure erasure or end-to-end encryption of its operation payloads.

## AI data flow

Generation sends subject, subtopic, ability, difficulty, question count, and mode. Grading sends only one question/reference, the submitted answer, hints used, and mode. Quest history, display name, calendar, and unrelated learning answers are not sent.

The gateway does not log prompt, answer, credential, or provider-response content. A small five-minute in-memory response cache deduplicates retries. Its disk state contains usage counters only. Provider retention and billing follow the account and API settings you configure; the app does not promise provider-side deletion or zero retention.

Problem reports remain in the app’s learning history and synchronize through private CloudKit. They are not automatically sent to the AI provider or an external support service.

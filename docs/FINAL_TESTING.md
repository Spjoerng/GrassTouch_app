# Final verification and offline capabilities

Automated verification runs on Windows with Flutter, SQLite FFI, native method-channel mocks, and widget tests. Android APK compilation verifies plugin integration. No native device gestures, tile rendering, operating-system file dialogs, or iOS/macOS builds are claimed as tested by those checks.

Recorded on 2026-10-16 after the UI polish and animation update: `flutter analyze` completed with no issues, all **82 tests** passed with `flutter test --concurrency=1`, and the Android debug build succeeded. The development APK is at `build/app/outputs/flutter-apk/app-debug.apk`. Sequential execution avoids observed Windows filesystem/SQLite timing contention in the widget-test harness; parallel runs can fail its fixed UI wait intervals.

After the live-location update, the expanded **84-test full suite** passed. A subsequent camera-cancellation safeguard and its new regression test passed all **3 live-location tests**; the analyzer remained clean and the Android debug APK was rebuilt successfully. Native movement, heading sensors, and vehicle behavior still require the device checks below.

After adding TouchGrass route-following mode, all **87 tests** passed with sequential execution, `flutter analyze` reported no issues, and `flutter build apk --debug` succeeded. The route-following checks use the fake map canvas and native bridge; they do not establish real-device GPS or compass accuracy.

On 2026-10-17, after fixing route-rename keyboard overlays and widening place details, all **91 tests** passed with `flutter test --concurrency=1`, the analyzer reported no issues, and the Android debug APK rebuilt successfully. Route-rename tests check phone and wide viewport/camera stability across keyboard frames; details tests cover a 320 px phone, larger text, photo viewing, accessible actions, and unchanged stored coordinate precision.

## Offline capability matrix

| Feature | Without internet | Requirement / recovery |
| --- | --- | --- |
| Place/collection/route CRUD, search, filters | Yes | Records are in SQLite; photo files must be present in app storage. |
| Photos and covers | Yes | Choose files already downloaded to the device. Missing files show a fallback and can be removed. |
| Journal ZIP backup, restore, GeoJSON | Yes | Local accessible file/destination and enough space for staged photos. A cloud document provider may itself need internet. |
| Road geometry, distance, duration from a saved route | Yes | Calculated result was saved; editing stops clears outdated geometry/metrics. |
| Calculate a new road route | No, with the default provider | Explicit OSRM request, bounded size/timeout, recoverable error. Save an uncalculated plan offline. |
| Current location | Often, depending on device | Foreground permission and enabled location services; no network guarantee for a fix. Manual coordinates remain available. |
| Live movement and facing direction | Device-dependent | My location explicitly enables native foreground updates and camera following. Compass heading requires a working sensor; it describes phone orientation, not necessarily vehicle travel. Stop control, panning/recenter, and background shutdown are supported. Physical GPS/compass accuracy is pending device verification. |
| Explore basemap | Conditional | Completed cached resources for the current style, geographic area, and zoom. Ordinary browsing is not guaranteed offline coverage. |
| Prepared offline area | Conditional | Compatible MapLibre Native `.db` import, verified complete status, matching resources, Android/iOS, and airplane-mode check. OS cache eviction remains possible. |
| Download map regions inside Fieldnotes | No | Obtain a completed compatible database using MapLibre preparation/export tooling. |
| Desktop interactive maps | No | Desktop retains offline journal/list functionality; native map workflow is Android/iOS only. |

## Automated checks

Run:

```sh
flutter analyze
flutter test
flutter build apk --debug
```

On Windows, use `flutter test --concurrency=1` for the full suite's real filesystem/SQLite widget tests.

| Area | Coverage |
| --- | --- |
| Journal | Complete place fields, create/read/update/delete, reopen, v1/v2/v3 migrations, constraints, ownership, collection membership/cover lifecycle, route waypoint/cache persistence, deletion safety. |
| Backup | Two independent databases, full graph transfer, matching and colliding local IDs, repeated merges, empty/full replace, checksums/version, unsafe ZIP entries, damaged data, reference/coordinate/geometry validation, duplicate-content photos, file-write and mid-transaction failure rollback. |
| Map integration | Style-load ordering/reload, clustered layers, overlap selection, filtering, camera requests, category pins, road source updates, disposal, offline zoom/clustering limits. |
| Performance | Unchanged place sources and roads are not reuploaded; a 10,000-place source stays unchanged through multiple selection updates. Uses a fake SDK; does not establish real-device FPS. |
| Routing | Longitude-first request order, metrics/geometry validation, HTTP/no-road/offline failures, stale-response rejection, streaming byte limits, request abort on planner close, cached-road preservation. |
| Lifecycle | Background suspends loading watchdogs; resume restarts with a bound, refreshes persisted journal/coverage status, rejects stale map callbacks and location results, and never prompts for location itself. |
| Local maps | Header/size/file-access validation, private staging and cleanup, native method-channel calls, complete/partial/unverified status, retry, cancelled picker, source preservation, confirmed area deletion preserving journal. Native map-database merge and rendering require the device checks below. |
| Layout | Phone/desktop navigation, phone map/list and filter flows, collection management, route editing, backup preview/restore/export, offline map management. |
| Place editor | Phone spacing above the name, hidden mobile coordinate fields, five tappable stars and clearing, map/current-location selection, permission-denial recovery, full coordinate precision, and cancelling a picker without losing the draft or previous pin. |
| Keyboard overlays | Seven regression checks keep the map rectangle, canvas state, and camera request unchanged through opening/closing keyboard frames on phone/wide Explore, route renaming, collection maps, and offline-area maps. Route renaming remains usable above the keyboard. List search and place-form actions still make room above the keyboard. |
| Place details | Wider phone panel, six-decimal coordinate display with unchanged stored precision, star summary, larger photo previews, full-width Edit action and a Delete/Close row. Layout/photo-viewer checks pass at 320 px and 390 px with 1.4 text scaling. Existing editing, photo removal, and confirmed-deletion workflows remain covered. |
| UI motion and search | Entrance animations settle without replaying on content updates, respect reduced motion and accessible navigation, and search clearing updates the visible field without replacing or resizing the map. |
| Live location | Native bridge verifies compass rendering, high-accuracy engine configuration, focus-before-follow ordering, pan dismissal/re-follow, disabling the engine, and avoiding place-source reuploads. Widget checks verify explicit activation, stop controls, preserving the chosen journal pin, and no automatic restart after backgrounding. A delayed-camera test ensures queued work cannot restart stopped tracking. These use fake SDK surfaces, not physical location sensors. |
| Route following | Phone UI opens a stored road in Follow route, retains geometry/stops while live, fits the full route, recenters, stays active after two simulated hours, stops explicitly, and returns without editing saved records or calling the router. Permission denial preserves the road and offers settings/retry. Physical movement and heading rely on the same native component as Explore and still require device testing. |

## Device release checklist — pending native verification

Use a spare/test device or emulator and a copy of the journal. Keep a known-good exported backup. These are manual acceptance steps, not completed results.

1. **Cold start/persistence:** create a visited and planned place with ratings/notes/photos, favorite one, organize them in multiple collections with a cover, and save calculated and uncalculated routes. Force-stop/relaunch; verify every field, photo, link, stop order, road line, and estimate. Rename/delete records, restart, and confirm cascades preserve unrelated places and snapshots.
2. **Device-to-device backup:** export using the actual share/save UI, transfer the ZIP to another device, restore into an empty and populated journal, and compare counts, photos/covers/captions, memberships, road geometry, and estimates. Repeat merge; verify no duplicates. Cancel replace; verify no changes. Try a corrupt/wrong-format file and a low-storage import; original journal must remain intact. GeoJSON must open in another compatible GIS/map tool.
3. **Map unavailable:** cold-start in airplane mode without map data. Wait for loading recovery, use the offline list, create/edit places manually, edit route stops, and reopen cached route geometry. Reconnect and reload basemap. Also pan beyond cached coverage after a successful style load; the list must remain reachable even when tiles are blank.
4. **Prepared local map:** create a completed MapLibre offline database for a small Batangas area with Bright style, its assets, and a documented zoom range. Checkpoint/export consistently and import the single file. Confirm complete status, bounds and zoom restrictions, clusters resolving to individual pins at the maximum zoom, overlap selection, and custom journal markers. Force-stop, enable airplane mode, relaunch, and inspect all needed zooms/labels/sprites. Import an incomplete database; it must not be presented as ready. Delete an area and verify journal records/photos/routes remain. On iOS, recheck status following storage pressure/cache eviction.
5. **Permissions/location:** test first permission request, deny, permanent deny, approximate grant, disabled services, slow GPS, and app-settings round trip. Tap My location and verify the native blue marker moves on a simulated route or real trip, its compass indicator responds to turning the phone, and the camera follows. Pan away and verify updates continue without recentering; tap My location to follow again. Verify the selected journal pin remains fixed, Stop live location disables updates, backgrounding stops tracking, and resume does not restart it or prompt. Test a device without reliable heading and a vehicle's magnetic interference; phone heading is distinct from travel direction. Background during a pending request, then deny/revoke in settings; select coordinates manually and confirm the journal remains usable.
6. **Files:** test Android document providers and iOS Files with downloaded and unavailable cloud files. Cancel each picker/share sheet. Revoke file access, use a missing file, and simulate insufficient storage. A cancelled export must not claim a saved external backup. On iPad verify share-sheet anchoring. On sandboxed macOS verify native import and export with the user-selected read/write entitlement.
7. **Lifecycle/interruptions:** background during routing, photo save, backup preparation, import, and map loading; return and verify bounded recovery without duplicate operations. Relaunch after interrupted transactions; SQLite must reopen, incomplete copies must not replace live photos, and queued cleanup must retry. Repeat map/list and route navigation to inspect map disposal and memory usage.
8. **Performance/layout:** profile a release/profile build on a midrange physical phone with thousands of spread-out and overlapping places, long routes, and large photos. Measure frame times, map interaction, memory, and source updates. Check a small phone, landscape, keyboard, large text, accessibility labels, and slow provider responses. Automated fake-SDK upload tests do not replace this profiling.
9. **Platform builds:** build/test iOS with macOS/Xcode and the repository's `tool/flutter_ios.sh` wrapper. Verify Android release signing/application ID separately; the debug APK is a development artifact. Run the desktop journal on each intended desktop target with its required toolchain.

Prepared map coverage and road routing are distinct. Do not advertise guaranteed offline basemaps, offline driving directions, background downloads/location, or cloud synchronization for this build.

# Fieldnotes

An offline-first Flutter place journal with personal places, collections, mobile MapLibre maps, route planning, portable backups, and a local offline map-data workflow.

## Run

Launcher icons use `assets/icon.png` over the app's forest green (`#254F40`). Android uses separate adaptive foreground/background layers; legacy Android, iOS, Windows, and macOS use the opaque generated master. To regenerate after changing the artwork:

```sh
dart run tool/prepare_launcher_icon.dart
dart run flutter_launcher_icons
```

Use Flutter matching the Dart SDK constraint in `pubspec.yaml`, then:

```sh
flutter pub get
flutter run -d windows
```

Android, iOS, macOS, Windows, and Linux use SQLite locally. Windows and Linux use `sqflite_common_ffi`; mobile and macOS use `sqflite`. Linux needs the system SQLite library. Web is not supported by this native storage implementation. Building Windows requires Visual Studio with the Desktop development with C++ workload; that toolchain is not installed in the current development environment.

## Personal place journal

- Create, view, edit, and delete places; deletion requires confirmation.
- Store names, validated coordinates, categories, notes, optional 1-5 ratings, optional visit dates, visit status, and independent favorite state.
- A place is either Visited or Want to visit. Visit dates are optional for visited places and are cleared when changing back to Want to visit. Tap one of five visual stars to rate a place; Clear rating returns it to unrated.
- The mobile place editor keeps numeric coordinate fields out of the form. A map-picked pin is retained automatically; Choose on map / Change location opens a visual picker, and Use current location requests a fix only when tapped. Cancelling the picker keeps the form draft and prior pin. The selected coordinates retain their full precision in storage. Desktop retains collapsed advanced coordinate entry when no native map is available. Place names have a persistent label and extra space below the dialog title.
- Search names, notes, and categories. Combine category and visit-status filters with Favorites only; Clear filters resets these selections.
- Choose one or more local JPEG, PNG, or WebP files using the native file selector. Thumbnails open a zoomable photo viewer. Missing or unreadable photos display a fallback and can still be removed.
- Photos are copied to app-owned attachment storage on Save. Cancelling edits leaves records and photos unchanged. Removing photos and deleting places removes owned copies; original source files are preserved.
- Place metadata and attachment changes commit in one SQLite transaction after new photo copies succeed. Failed saves preserve the original record. Removed files use a durable cleanup queue; locked files are retried after another save or on reopening the app.
- Journal operations, search, filters, and saved photo viewing require no account, network, map provider, or cloud service. Choose files already downloaded to the device for offline photo import.

## Interactive map (Stage 03)

- Explore uses a full-height map above compact navigation, with floating search, a List shortcut, and location/fit/options controls. Category, visit-status, and favorites filters open from the search bar in an Apply/Cancel bottom sheet. Map information and offline notes live in Map info, while native source attribution remains on the map.
- Explore opens the Map view; My Places opens the List view. Both use the same SQLite records and the same search, category, visit-status, and favorites filters. Switching views keeps the filters.
- Keyboards overlay map views without resizing or recreating the map viewport. Explore preserves navigation/system padding during keyboard animation; collection and offline-area maps follow the same behavior. Renaming routes also preserves the route map viewport and bottom system padding. List views and place forms still resize above the keyboard.
- Category-based custom PNG pins are drawn locally with Material icons: Nature, Food & drink, Culture, Stay, and Other. Unknown categories use Other. The map info button includes a legend.
- Nearby pins cluster natively at low zoom, with count labels. Tap a cluster to zoom to its expansion level. Clustering ends above zoom 14. Overlapping individual pins offer a place-selection panel.
- Tap a pin to view, edit, or delete the existing journal entry. Map data refreshes after changes. Tap an empty map position to preview coordinates, then Save this place to open a prefilled place editor. Nothing is saved until the form is submitted.
- My location checks services and foreground permission on demand, obtains a bounded high-accuracy fix, centers the camera, and selects those coordinates for optional saving. MapLibre then provides continuous foreground updates: the blue marker moves as you travel and its compass indicator shows the phone's facing direction when heading data is available. Pan to explore; tap My location to follow again. Stop using the live-status close button or Map options → Stop live location. Backgrounding stops tracking; returning never restarts or prompts automatically. Selected journal pins stay fixed independently of live movement. Compass accuracy depends on the device and surroundings, particularly inside vehicles; phone heading can differ from travel direction. Initial denial, permanent denial, disabled services, timeout, and fix failures have recovery messages and settings links. No startup prompt or background-location permission is used.
- The initial map view centers on the Batangas area, Philippines (13.9, 121.05 at zoom 9). Saved places do not override this starting view. Fit places fits the currently filtered markers. Reload basemap recreates the map without changing journal records or filters. A loading timeout offers retry and an offline list fallback.

### Platform support and basemap

[`maplibre_gl`](https://pub.dev/packages/maplibre_gl) supports Android and iOS native maps. This app's SQLite implementation is native-only, so the package's browser support is not enabled here. Native Windows, macOS, and Linux retain the full journal/list and show a map-platform fallback instead of creating an unsupported platform view.

The default [OpenFreeMap Bright style](https://openfreemap.org/quick_start/) configures the vector tile source, glyphs, sprites, and attribution. No API key is required. The source attribution control stays available on the map; default data credits include OpenFreeMap, OpenMapTiles, and OpenStreetMap contributors. To use another compatible provider at build time:

```sh
flutter run --dart-define=MAP_STYLE_URL=https://your-provider.example/style.json
```

The map consumes an inline GeoJSON source containing only local place IDs, category marker keys, and coordinates; journal notes and photo paths are not passed to the basemap source. Tile requests still reveal the viewed geographic area to the provider.

Basemap display requires internet or map resources already available locally, including the style, tiles, glyphs, and sprites. Incidental SDK caching is not a guarantee of offline coverage. Use the Offline maps screen to import and verify prepared MapLibre offline databases; see the workflow below. SQLite records, search, filters, photos, and manual-coordinate entry remain usable offline regardless of tile availability.

### Native setup and running

Android's main manifest includes internet and foreground coarse/fine location permissions, including release builds. Approximate location grants are accepted. JDK 21 and the Android SDK/build tools required by MapLibre must be available. To build:

```sh
flutter build apk --debug
```

For iOS, the project targets iOS 13+ and includes `NSLocationWhenInUseUsageDescription`. This project uses Swift Package Manager. On macOS, use the wrapper below so geolocator's foreground-only compilation flag is set during package resolution:

```sh
sh tool/flutter_ios.sh run -d <iphone-device-id>
sh tool/flutter_ios.sh build ios
```

If switching to CocoaPods, apply the `BYPASS_PERMISSION_LOCATION_ALWAYS=1` post-install flag from the [geolocator setup documentation](https://pub.dev/packages/geolocator). No Always or background-location permission is needed by this app.

Map tests inject a canvas boundary rather than claiming to render a native GPU map inside Flutter widget tests. They cover shared filters/records, marker-to-details navigation, saving tapped coordinates, explicit permission requests, location recovery, camera intents, map retry and offline-list fallback, custom marker images, and GeoJSON conversion. A separate test drives the real MapLibre widget/controller bridge with a fake SDK to verify style-load ordering, clustered-source configuration, cluster expansion taps, overlapping marker selection, source replacement after filtering, and disposal. Physical-device smoke testing is still needed for native gestures, cluster expansion, tile-provider reachability, attribution controls, and actual operating-system permission dialogs. iOS builds require macOS/Xcode and have not been run in this Windows environment.

## Collections and organization (Stage 04)

- Create custom collections, rename them, edit descriptions, and delete them with confirmation. Suggested names such as Weekend plans, Favorite restaurants, and Study spots open a prefilled editor; they do not create records until saved.
- A place can belong to multiple collections. Manage places selects membership from all saved places, with search and a selection count. Selections hidden by search are preserved. Save places commits the complete change atomically; Cancel leaves membership unchanged.
- Open a collection for its own list and map views. Search and category, visit-status, and favorites filters apply to that collection only and persist between its views. Collection filters are independent of the main journal filters.
- Remove from collection on a list card removes membership only. Editing a place updates its shared journal record in every collection. Deleting a place from its details removes the actual journal entry and cascades its memberships.
- Tap the collection map to create a new place. The new journal entry and its collection membership save in the same transaction.
- Add an optional local JPEG, PNG, or WebP cover image. Cover files are copied on Save into private storage, with portable relative paths. Cancelled edits leave the existing cover untouched. Replaced/removed covers use the same retryable file cleanup queue as journal photos.
- Deleting a collection removes its cover copy and memberships, while preserving all saved places, journal photos, original cover source files, and other collections. Collection metadata and list organization remain fully offline; map tiles have the same availability requirements as Explore.

`lib/src/collections.dart` contains the index, collection details, and membership editor. `lib/src/collection_dialog.dart` handles collection metadata and staged cover edits. Repository tests cover persistence, migration, shared membership, transaction rollback, cover lifecycle, and deletion safety. Phone-sized UI tests cover organizing, filtering, map/list switching, renaming, confirmed deletion, and cover cancellation.

## Route planning (Stage 05)

- Create a route in Routes, add a starting point and destination, and include up to 25 ordered stops. Choose saved places, enter coordinates, or pick positions on the map. S and D identify the start and destination; intermediate stops are numbered.
- Switch between the route map and Stops. Drag stop circles to reorder, or use each stop's menu to move up/down, remove, or position it on the map. Tap a waypoint and then a new map position to move it. Editing a route waypoint does not move the original journal place.
- Calculate road route explicitly requests a driving route from the public OSRM demo service. Requests preserve stop order and ask for full GeoJSON LineString geometry. A white-cased green polyline shows the returned road path. Distances and travel times come from the provider and do not include live traffic.
- Save routes with or without a calculated road path. Saved ordered waypoint snapshots, geometry, distance, and duration restore without requesting routing again. Source-place deletion removes the reference but keeps the route's stop snapshot and geometry.
- Once a road path is available, Follow route opens a dedicated map with the stored geometry, stop markers, live foreground movement, and phone compass direction. Pan or Fit route to inspect the path, then tap My location to follow again. It stays open until you stop location or choose End following; arrival does not end it automatically. Backgrounding stops live tracking, which can be restarted explicitly. Following does not change stops, save edits, or send routing requests. This is a route overview with total estimates, without turn-by-turn instructions or automatic rerouting.
- Rename, edit, and delete saved routes. Deleting a route removes its waypoints, not its journal places. Leaving a changed route prompts before discarding unsaved edits.
- Moving, adding, removing, or reordering stops immediately clears stale road geometry and estimates. Late routing responses are ignored if the stops changed while the request was running. Renaming a route keeps its calculated path.
- If routing fails, an unchanged cached path remains available. Modified plans can still save offline with no stale metrics. Network failures, no-road results, malformed responses, and timeouts have recovery messages. No straight-line connection is presented as a road route.

The default service is `https://router.project-osrm.org`, using the [OSRM Route API](https://project-osrm.org/docs/v26.5.0/http). A live check with fixed public Batangas coordinates returned full road geometry and metrics. Calculation sends stop coordinates to the provider only when requested by the user; journal notes and photos are not sent. Requests are limited to one per second per router and are never automatically issued while moving stops. The public demo has no availability guarantee; use a suitable hosted or self-hosted OSRM deployment for sustained production usage:

```sh
flutter run --dart-define=ROUTING_BASE_URL=https://your-osrm.example
```

The override is an OSRM server base URL; `/route/v1/driving/...` is appended. This stage supports driving only. Current-location controls remain in Explore, and route stops can be positioned manually without location permission. Basemap resources still need network access or locally available data; cached route geometry alone does not guarantee offline basemap coverage.

`lib/src/routes/route_models.dart` defines immutable stops and validated road results. `road_router.dart` owns provider requests and errors. `route_draft.dart` handles waypoint changes, cache invalidation, and stale-response protection. `route_planner.dart` provides route browsing, stop selection/editing, and the planner. Route writes replace waypoints and cached geometry/metrics atomically; schema v4 also supplies portable identities for backups.

Tests cover request order/coordinate encoding, response validation and failures, route reopening, rollback, stale-cache protection, source-place deletion, route deletion safety, phone editing/reordering/map placement, offline route plans, rename/delete, discard confirmation, and MapLibre polyline source updates. Physical-device checks are still needed for native gestures and provider routing across real trip areas; iOS has not been built in this Windows environment.

## Backup, import, and export (Stage 06)

Open **Backup & export** from Explore's journal menu or the backup icon in My Places, Collections, and Routes. Export backup packages every place field, collection description/cover, membership, route, ordered waypoint, cached road geometry/metrics, and photo caption/file. Android and iOS open the native share sheet; choose an appropriate Files/storage destination and verify the file there. Desktop opens a save dialog. Cancelling a dialog does not claim that a backup was saved. Mobile export working copies live in the app's temporary directory and are not a substitute for saving an external copy.

Choose backup validates a ZIP and displays its record counts before offering two restore modes:

- **Merge** keeps local fields for matching portable record IDs, adds missing records/photos, and unions collection memberships. Existing matching route plans and their waypoints remain intact. Importing the same backup repeatedly avoids duplicate records. Separate records with identical names remain separate.
- **Replace** requires confirmation and replaces the journal with the validated snapshot. It also supports restoring an empty journal. Export the current journal first to keep a copy of records that are absent from the incoming backup.

Schema v4 adds random 128-bit `stable_id` identities to places, collections, routes, waypoints, and attachments, backfilling existing records during migration. These IDs remain unchanged across devices. Local integer primary keys are preserved when free and remapped on merge collisions; all foreign keys and memberships follow the remapping. The backup's integer references are scoped to that archive, while portable IDs establish identity across archives.

The version 1 ZIP layout is `manifest.json`, `journal.json`, and `media/<sha256>[.<extension>]`. The manifest declares `format: fieldnotes-journal`, `version: 1`, its UTC creation date, and every data/media file's byte length and SHA-256 checksum. `journal.json` contains the six database record arrays, including stable identities and photo/cover references to media entries. Media with identical bytes and extensions is deduplicated inside the archive; restored attachment files receive separate safe local names. Device-specific absolute paths and SQLite files are not exported. Backups are unencrypted and include personal notes and photos; checksums detect corruption, not authorship.

Import checks format version, ZIP entries/CRC, checksums, required column types, unique identities/IDs, coordinates, ratings, geometry, waypoint order, and every photo/foreign-key reference before modifying the journal. It rejects traversal paths, symlinks, encrypted entries, duplicate ZIP entries, undeclared/missing media, unsupported versions, and oversized data. Limits are 128 MB compressed, 256 MB expanded or restored media, 32 MB per file, 10,002 ZIP entries, and 100,000 total records. ZIP compression/decompression and JSON processing run off the UI isolate. Photos are staged under fresh names with a durable cleanup queue; database replacement and reference remapping commit atomically. On failure, the transaction rolls back and existing photo files remain untouched. Retired or abandoned files are cleaned after completion or next startup; locked files are retried.

GeoJSON export produces a WGS84 FeatureCollection with longitude/latitude place points, collection membership properties, route features containing cached LineStrings and estimates, and separate waypoint points. Uncalculated route features have null geometry and retain their stop metadata; no road lines are invented. GeoJSON does not embed photos and is an interchange export, not a full-journal restore format. Use ZIP for transferring the complete journal. Basemap tiles and offline map regions are not included in either export.

Tests transfer the complete graph between independent databases, preserve photos/covers with duplicate content, reopen restored data, remap colliding local IDs, repeat merges, reject corrupt archives, and inject transaction failure after replacement starts to verify rollback and file safety. Phone widget tests exercise preview, replacement cancellation, merge, invalid-file recovery, and export boundaries. Native picker/share-sheet behavior still requires Android/iOS device smoke testing; iOS and macOS builds have not been run on this Windows host.

## Offline improvements and final testing

Open **Offline maps** from Explore's journal menu or the offline icon on the other tabs. This stage provides a supported **local map-data import workflow**, rather than in-app region downloads:

1. Obtain a completed **MapLibre Native offline SQLite database** with region definitions, style JSON, tiles, fonts, and sprites. Use the preparation/export APIs in the [MapLibre offline guide](https://maplibre.org/flutter-maplibre-gl/advanced/offline-regions/), or compatible MapLibre Native tooling. MBTiles, PMTiles, ordinary SQLite journals, and ZIP backups are different formats. Prepare the same Bright style URL used by Explore to reuse coverage there. A custom style is opened in its own area view. Include the `Noto Sans Regular` glyph range covering digits and S/D used by journal cluster/waypoint labels.
2. Stop all writes/downloads before exporting the map store. Transfer a consistent, **checkpointed single `.db` file**, up to 512 MB. If a preparation tool exports SQLite WAL sidecars, place the exported copy and its sidecars together, checkpoint that copy with SQLite (`PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;`), close it, and then transfer the resulting database. Do not modify a live application's map cache.
3. Import the file in Offline maps on Android/iOS. The app checks its size and SQLite header, copies it into private temporary staging, and delegates map-schema validation/merge to MapLibre. Staging is removed on completion or failure, and the original file is preserved. The map store is separate from SQLite journal storage; importing or deleting map data never replaces journal records.
4. Check each area's native completeness status. Partial or unverified areas cannot be opened as prepared coverage; import a completed replacement and refresh. Areas can be removed with confirmation. Status refreshes when the app resumes because the OS, especially iOS under low storage, may evict cached resources.
5. Open a complete area to browse the shared journal records and filters with that area's style, camera bounds, and zoom range. Native clustering ends before the area's maximum zoom so pins can be selected there. Switch to the list if a tile is missing; edges outside prepared coverage may be blank. Test the exact area and zooms in airplane mode before a trip.

No bulk downloads run in this app. Anyone preparing data from OpenFreeMap must follow its [offline-use terms](https://openfreemap.org/): a download is limited to 3,000 tiles or 50 MB, with no more than four concurrent requests and an app-identifying User-Agent; use an appropriately licensed/self-hosted source for larger preparations. Offline map databases are separate from journal ZIP backups. Importing a map does not enable offline road routing or guarantee coverage beyond its saved resources.

### Reliability and performance changes

- Explore and route maps offer a bounded 25-second style-loading timeout with retry and an offline list/Stops fallback. Timers pause while backgrounded and restart on return. Missing tiles do not prevent saving places, editing coordinates, or reopening cached road geometry. A loaded style does not prove all visible tiles were fetched; Map info / missing tiles explains the distinction.
- Returning from device settings never prompts for location automatically. Late location fixes from before backgrounding are ignored, and the old location dot is cleared. Saved selected coordinates remain explicit journal input. The shell reloads persisted records when resumed.
- Native style reloads rebuild custom sources, layers, and images. Marker PNG bytes are cached across map lifetimes. Only changed coordinate/category/ID sets are converted and uploaded to the clustered place source; private note edits do not resend it. Selection, location, route geometry, and route stops update independently, and queued rebuilds are coalesced. Unused per-camera-position tracking is disabled. Place lists compute their filtered records once per list build, instead of filtering the whole journal per visible row.
- Routing responses are bounded to 10 MB during streaming, including responses without Content-Length. Header/body fetches share a 20-second timeout; abortable requests are cancelled after completion/failure or when the planner closes. Existing plans and cached roads remain usable when the provider is unavailable.

The tests exercise CRUD/reopening/migrations, backup graph/photo/cover integrity, stable-ID collision remapping and idempotent merge, invalid imports and transaction/photo-write failure rollback, denied location permission, missing-map fallback, background/resume and stale callbacks, offline file access/cancellation, incomplete coverage, native method-channel arguments, native style recreation, and independent source updates with 10,000 places. The large-source test verifies upload behavior through a fake SDK, not device frame rate or GPU performance. See [the final test matrix](docs/FINAL_TESTING.md) for release/device checks and remaining platform limitations.

## Foundation and storage

The responsive Material 3 shell includes Explore, My Places, Collections, and Routes, with bottom navigation on phones and a navigation rail on wide screens. Collections support descriptions, local cover images, membership editing, and scoped list/map browsing.

SQLite schema v4 includes places, collections, collection membership, routes, ordered waypoint snapshots, attachment metadata, and a photo cleanup queue. Sequential migrations preserve existing records, add optional collection cover paths, and backfill portable identities. Foreign keys, cascading deletes, coordinate/rating constraints, and transactional route replacement protect consistency. Attachments use relative paths in private storage and archive-relative media references in backups.

The database and attachments live in the platform's application support directory. File selection uses `file_selector`, with extension, MIME, and Apple type filters following its [official documentation](https://pub.dev/packages/file_selector). macOS includes user-selected read/write file access for importing and saving exports. Mobile exports use [share_plus](https://pub.dev/packages/share_plus); no broad storage or photo-library permission is requested by this workflow.

## Structure

- `lib/main.dart`: startup and storage initialization.
- `lib/src/app.dart`: theme, navigation, record loading, and shared filter state.
- `lib/src/place_browser.dart`: shared map/list browsing, filters, marker details, and coordinate-to-place creation.
- `lib/src/map/`: MapLibre layers, custom pin generation, GeoJSON conversion, map controls, and testable location permission handling.
- `lib/src/map/offline_maps.dart` and `offline_maps_page.dart`: supported map database import, native coverage status, deletion, and area browsing.
- `lib/src/place_journal.dart`: place details, editor, native photo selection, and viewer.
- `lib/src/data/journal_store.dart`: SQLite schema, migration, journal transactions, attachment metadata, and deferred deletion.
- `lib/src/data/attachment_storage.dart`: private file copies and path confinement.
- `lib/src/data/place_filter.dart`: combined search/filter matching.
- `lib/src/backup/`: versioned ZIP format, archive validation, transactional restoration, GeoJSON export, and native import/export UI.

## Validation

The interface uses shared forest-green navigation, outlined cards, and consistent form spacing. Lists enter with a short fade and slide; rating stars respond with a subtle scale animation. These animations respect reduced-motion and accessible-navigation settings. Map canvases stay outside entrance animations, and clearing search preserves the map viewport.

```sh
flutter analyze
flutter test
```

Tests cover complete field persistence, database reopening, v1 migration, constraints, transactional rollback, photo ownership, source-file independence, failed copies, deferred file cleanup, foreign keys, path traversal rejection, combined filters, phone and desktop navigation, full journal entry creation, date/rating/status edits, cancelling photo changes, offline photo viewing and removal, picker failures, and confirmed place deletion. Native file-picker dialogs still need device smoke testing.

## Later stages

In-app offline region downloads, additional routing profiles/providers, and offline route calculation remain future work. Prepared MapLibre database import is supported now. Route metrics stay nullable until supplied by a routing provider. Future database and backup format changes must include migrations or explicit version handling that preserve existing journals.

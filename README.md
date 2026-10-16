# Fieldnotes

An offline-first Flutter place journal. Stages 01-04 provide the native app foundation, personal place journal, mobile MapLibre integration, and custom collections.

## Run

Use Flutter matching the Dart SDK constraint in `pubspec.yaml`, then:

```sh
flutter pub get
flutter run -d windows
```

Android, iOS, macOS, Windows, and Linux use SQLite locally. Windows and Linux use `sqflite_common_ffi`; mobile and macOS use `sqflite`. Linux needs the system SQLite library. Web is not supported by this native storage implementation. Building Windows requires Visual Studio with the Desktop development with C++ workload; that toolchain is not installed in the current development environment.

## Personal place journal

- Create, view, edit, and delete places; deletion requires confirmation.
- Store names, validated coordinates, categories, notes, optional 1-5 ratings, optional visit dates, visit status, and independent favorite state.
- A place is either Visited or Want to visit. Visit dates are optional for visited places and are cleared when changing back to Want to visit. Ratings can be cleared using Not rated.
- Search names, notes, and categories. Combine category and visit-status filters with Favorites only; Clear filters resets these selections.
- Choose one or more local JPEG, PNG, or WebP files using the native file selector. Thumbnails open a zoomable photo viewer. Missing or unreadable photos display a fallback and can still be removed.
- Photos are copied to app-owned attachment storage on Save. Cancelling edits leaves records and photos unchanged. Removing photos and deleting places removes owned copies; original source files are preserved.
- Place metadata and attachment changes commit in one SQLite transaction after new photo copies succeed. Failed saves preserve the original record. Removed files use a durable cleanup queue; locked files are retried after another save or on reopening the app.
- Journal operations, search, filters, and saved photo viewing require no account, network, map provider, or cloud service. Choose files already downloaded to the device for offline photo import.

## Interactive map (Stage 03)

- Explore uses a full-height map above compact navigation, with floating search, a List shortcut, and location/fit/options controls. Category, visit-status, and favorites filters open from the search bar in an Apply/Cancel bottom sheet. Map information and offline notes live in Map info, while native source attribution remains on the map.
- Explore opens the Map view; My Places opens the List view. Both use the same SQLite records and the same search, category, visit-status, and favorites filters. Switching views keeps the filters.
- Category-based custom PNG pins are drawn locally with Material icons: Nature, Food & drink, Culture, Stay, and Other. Unknown categories use Other. The map info button includes a legend.
- Nearby pins cluster natively at low zoom, with count labels. Tap a cluster to zoom to its expansion level. Clustering ends above zoom 14. Overlapping individual pins offer a place-selection panel.
- Tap a pin to view, edit, or delete the existing journal entry. Map data refreshes after changes. Tap an empty map position to preview coordinates, then Save this place to open a prefilled place editor. Nothing is saved until the form is submitted.
- My location requests one foreground location fix on demand, centers the camera, draws a blue dot, and selects those coordinates for optional saving. No startup prompt, continuous tracking, or background location is used. Denial, permanent denial, disabled services, timeout, and sensor failures have recovery messages; appropriate settings links are provided.
- The initial map view centers on the Batangas area, Philippines (13.9, 121.05 at zoom 9). Saved places do not override this starting view. Fit places fits the currently filtered markers. Reload basemap recreates the map without changing journal records or filters. A loading timeout offers retry and an offline list fallback.

### Platform support and basemap

[`maplibre_gl`](https://pub.dev/packages/maplibre_gl) supports Android and iOS native maps. This app's SQLite implementation is native-only, so the package's browser support is not enabled here. Native Windows, macOS, and Linux retain the full journal/list and show a map-platform fallback instead of creating an unsupported platform view.

The default [OpenFreeMap Bright style](https://openfreemap.org/quick_start/) configures the vector tile source, glyphs, sprites, and attribution. No API key is required. The source attribution control stays available on the map; default data credits include OpenFreeMap, OpenMapTiles, and OpenStreetMap contributors. To use another compatible provider at build time:

```sh
flutter run --dart-define=MAP_STYLE_URL=https://your-provider.example/style.json
```

The map consumes an inline GeoJSON source containing only local place IDs, category marker keys, and coordinates; journal notes and photo paths are not passed to the basemap source. Tile requests still reveal the viewed geographic area to the provider.

Basemap display requires internet or map resources already available locally, including the style, tiles, glyphs, and sprites. SDK caching is not a guarantee of offline coverage. Stage 03 does not download offline regions or promise complete offline maps. SQLite records, search, filters, photos, and manual-coordinate entry remain usable offline. Configure a permitted tile source and an explicit download/cache workflow before adding guaranteed offline map coverage.

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

## Foundation and storage

The responsive Material 3 shell includes Explore, My Places, Collections, and Routes, with bottom navigation on phones and a navigation rail on wide screens. Collections support descriptions, local cover images, membership editing, and scoped list/map browsing.

SQLite schema v3 includes places, collections, collection membership, routes, ordered waypoint snapshots, attachment metadata, and a photo cleanup queue. Sequential v1/v2-to-v3 migrations preserve existing places, photos, collection descriptions, and memberships while adding optional collection cover paths. Foreign keys, cascading deletes, coordinate/rating constraints, and transactional route replacement protect consistency. Attachments use relative paths for future portable archives.

The database and attachments live in the platform's application support directory. File selection uses `file_selector`, with extension, MIME, and Apple type filters following its [official documentation](https://pub.dev/packages/file_selector). macOS includes user-selected read-only file access entitlements. No broad storage or photo-library permission is requested by this file-selection workflow.

## Structure

- `lib/main.dart`: startup and storage initialization.
- `lib/src/app.dart`: theme, navigation, record loading, and shared filter state.
- `lib/src/place_browser.dart`: shared map/list browsing, filters, marker details, and coordinate-to-place creation.
- `lib/src/map/`: MapLibre layers, custom pin generation, GeoJSON conversion, map controls, and testable location permission handling.
- `lib/src/place_journal.dart`: place details, editor, native photo selection, and viewer.
- `lib/src/data/journal_store.dart`: SQLite schema, migration, journal transactions, attachment metadata, and deferred deletion.
- `lib/src/data/attachment_storage.dart`: private file copies and path confinement.
- `lib/src/data/place_filter.dart`: combined search/filter matching.

## Validation

```sh
flutter analyze
flutter test
```

Tests cover complete field persistence, database reopening, v1 migration, constraints, transactional rollback, photo ownership, source-file independence, failed copies, deferred file cleanup, foreign keys, path traversal rejection, combined filters, phone and desktop navigation, full journal entry creation, date/rating/status edits, cancelling photo changes, offline photo viewing and removal, picker failures, and confirmed place deletion. Native file-picker dialogs still need device smoke testing.

## Later stages

Offline region downloads, route-planning UI, routing providers, backup/restore, and GeoJSON export remain future work. Route metrics stay nullable until supplied by a routing provider. Future schema changes must include migrations that preserve existing journals.

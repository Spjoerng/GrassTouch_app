#!/usr/bin/env sh
# geolocator_apple reads this during Swift Package Manager manifest resolution.
# This app requests only foreground, user-initiated location fixes.
export BYPASS_PERMISSION_LOCATION_ALWAYS=1
exec flutter "$@"

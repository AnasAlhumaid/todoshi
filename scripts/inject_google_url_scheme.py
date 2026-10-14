#!/usr/bin/env python3
"""DEPRECATED — do not use for production builds.

Previously attempted to inject Google Sign-In REVERSED_CLIENT_ID into the *built*
Info.plist. That approach failed on device because:

1. When Google Auth was first wired, GoogleService-Info.plist lacked REVERSED_CLIENT_ID,
   so the script exited without changing anything.
2. Even after the plist was refreshed, mutating TARGET_BUILD_DIR/INFOPLIST_PATH is
   fragile: Xcode may process/copy Info.plist around signing, and a silent no-op
   (missing env vars / missing file) leaves the shipped app without the scheme.

Google URL schemes now live deterministically in:
  Todoshi/Resources/Info.plist → CFBundleURLTypes

Kept only as historical reference.
"""

raise SystemExit(
    "inject_google_url_scheme.py is deprecated; "
    "configure CFBundleURLTypes in Todoshi/Resources/Info.plist instead."
)

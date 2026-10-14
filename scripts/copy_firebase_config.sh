#!/bin/sh
# Copies the developer-local GoogleService-Info.plist into the app bundle when present.
FIREBASE_PLIST="${SRCROOT}/Todoshi/Resources/GoogleService-Info.plist"
DEST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"

if [ -f "$FIREBASE_PLIST" ]; then
  cp "$FIREBASE_PLIST" "$DEST"
else
  rm -f "$DEST"
fi

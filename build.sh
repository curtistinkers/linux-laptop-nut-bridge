#!/bin/sh
set -e

# 1. Dynamically locate the script's active directory location
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
PACKAGE_NAME="linux-laptop-nut-bridge"
OUTPUT_DEB="${SRC_DIR}/../${PACKAGE_NAME}.deb"
TMP_STAGE="/tmp/deb-build-${PACKAGE_NAME}"

echo "==> Cleaning old build targets..."
rm -f "$OUTPUT_DEB"
rm -rf "$TMP_STAGE"
mkdir -p "$TMP_STAGE"

echo "==> Isolating and copying only package directories..."
cd "$SRC_DIR"

for folder in DEBIAN usr etc lib; do
    if [ -d "$folder" ]; then
        # Find and copy only payload files, maintaining identical parent directories
        find "$folder" -type f -exec cp --parents {} "$TMP_STAGE/" \;
    fi
done

echo "==> Compiling production-ready .deb package..."
dpkg-deb --build "$TMP_STAGE" "$OUTPUT_DEB"

# Scrub the temporary scratch directory immediately
rm -rf "$TMP_STAGE"
echo "Successfully generated: $(basename "$OUTPUT_DEB")"

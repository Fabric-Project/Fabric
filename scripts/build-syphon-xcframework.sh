#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${REPO_ROOT}/Syphon/Syphon.xcodeproj"
SCHEME="Syphon"
CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_DIR="${1:-${REPO_ROOT}/Frameworks}"
OUTPUT_XCFRAMEWORK="${OUTPUT_DIR}/Syphon.xcframework"

if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "error: missing project at ${PROJECT_PATH}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/syphon-xcframework.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

DERIVED_DATA="${TMP_DIR}/derived-universal"

echo "Building Syphon.framework (${CONFIGURATION}, arm64+x86_64)..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk macosx \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  build

UNIVERSAL_FRAMEWORK="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Syphon.framework"

if [[ ! -d "${UNIVERSAL_FRAMEWORK}" ]]; then
  echo "error: missing built framework at ${UNIVERSAL_FRAMEWORK}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
rm -rf "${OUTPUT_XCFRAMEWORK}"

echo "Creating ${OUTPUT_XCFRAMEWORK}..."
xcodebuild -create-xcframework \
  -framework "${UNIVERSAL_FRAMEWORK}" \
  -output "${OUTPUT_XCFRAMEWORK}"

if [[ ! -d "${OUTPUT_XCFRAMEWORK}" ]]; then
  echo "error: xcframework output not found at ${OUTPUT_XCFRAMEWORK}" >&2
  exit 1
fi

if [[ ! -f "${OUTPUT_XCFRAMEWORK}/Info.plist" ]]; then
  echo "error: xcframework is missing Info.plist at ${OUTPUT_XCFRAMEWORK}/Info.plist" >&2
  exit 1
fi

echo "Done: ${OUTPUT_XCFRAMEWORK}"
echo "Validated: ${OUTPUT_XCFRAMEWORK}/Info.plist"

#rm -rf "${OUTPUT_XCFRAMEWORK}"

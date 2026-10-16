#!/usr/bin/env bash
#
# Removes the Fabric payload Xcode copies into a .fabricplugin bundle.
#
# A plugin links Fabric.framework without embedding it, but Xcode still copies
# the resource bundles of every package target in Fabric's dependency closure
# and embeds Fabric's binary frameworks. The host application already ships all
# of them, and Fabric.framework only ever loads the host's copies, so the
# plugin's copies are dead weight.
#
# Run it as the last Run Script build phase of the plugin target (see
# PLUGINS.md), where Xcode signs the bundle afterwards. Outside Xcode, pass
# the plugin bundle's path, then re-sign it:
#
#   scripts/strip-fabric-plugin-payload.sh path/to/MyPlugin.fabricplugin
#   codesign --force --sign <identity> path/to/MyPlugin.fabricplugin
#
# To keep one of the listed items, name it in the FABRIC_PLUGIN_KEEP build
# setting or environment variable (space separated), e.g.
# FABRIC_PLUGIN_KEEP="mlx-swift_Cmlx.bundle".
#
# Keep these lists in step with Package.swift: when Fabric gains a dependency
# that carries resources or a binary framework, add it here.

set -euo pipefail

FABRIC_RESOURCE_BUNDLES=(
  "Fabric_Fabric.bundle"
  "Satin_Satin.bundle"
  "mlx-swift_Cmlx.bundle"
  "swift-transformers_Hub.bundle"
  "swift-crypto_Crypto.bundle"
  "swiftui-math_SwiftUIMath.bundle"
  "textual_Textual.bundle"
)

FABRIC_EMBEDDED_FRAMEWORKS=(
  "Syphon.framework"
  "HapInAVFoundation.framework"
)

if [[ $# -gt 0 ]]; then
  BUNDLE_DIR="${1%/}"
  RUN_BY_HAND=1
elif [[ -n "${TARGET_BUILD_DIR:-}" && -n "${CONTENTS_FOLDER_PATH:-}" ]]; then
  BUNDLE_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH%/Contents}"
  RUN_BY_HAND=0
else
  echo "error: run from an Xcode build phase, or pass the .fabricplugin path" >&2
  exit 1
fi

# Everything listed here is something a host application needs, so refuse any
# bundle Fabric would not load as a plugin.
if [[ "${BUNDLE_DIR}" != *.fabricplugin ]]; then
  echo "error: ${BUNDLE_DIR} is not a .fabricplugin bundle; nothing removed" >&2
  exit 1
fi

CONTENTS_DIR="${BUNDLE_DIR}/Contents"

if [[ ! -d "${CONTENTS_DIR}" ]]; then
  echo "error: no bundle contents at ${CONTENTS_DIR}" >&2
  exit 1
fi

KEPT_ITEMS=" ${FABRIC_PLUGIN_KEEP:-} "
REMOVED_COUNT=0

remove_item() {
  local item_path="$1"
  local item_name
  item_name="$(basename "${item_path}")"

  [[ -e "${item_path}" ]] || return 0

  if [[ "${KEPT_ITEMS}" == *" ${item_name} "* ]]; then
    echo "Keeping ${item_name}"
    return 0
  fi

  rm -rf "${item_path}"
  REMOVED_COUNT=$((REMOVED_COUNT + 1))
  echo "Removed ${item_name}"
}

for bundle_name in "${FABRIC_RESOURCE_BUNDLES[@]}"; do
  remove_item "${CONTENTS_DIR}/Resources/${bundle_name}"
done

for framework_name in "${FABRIC_EMBEDDED_FRAMEWORKS[@]}"; do
  remove_item "${CONTENTS_DIR}/Frameworks/${framework_name}"
done

# Leave no empty Frameworks folder behind.
if [[ -d "${CONTENTS_DIR}/Frameworks" ]]; then
  rmdir "${CONTENTS_DIR}/Frameworks" 2>/dev/null || true
fi

# In a build phase Xcode signs afterwards. A bundle stripped by hand was
# usually signed already, and removing sealed resources has broken that seal.
if [[ "${RUN_BY_HAND}" == 1 && "${REMOVED_COUNT}" -gt 0 && -d "${CONTENTS_DIR}/_CodeSignature" ]]; then
  echo "warning: ${BUNDLE_DIR} was signed before stripping and its signature is now invalid; re-sign it:" >&2
  echo "  codesign --force --sign <identity> \"${BUNDLE_DIR}\"" >&2
fi

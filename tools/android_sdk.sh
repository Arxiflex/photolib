#!/usr/bin/env bash
# Installs Android SDK packages, such as the NDK Flutter builds with or an emulator's system image, with the SDK's
# sdkmanager and checks that each one is installed: sdkmanager may exit 0 after a broken download ("Error on ZipFile
# unknown archive"). A package that is not installed is fetched once more, from scratch, before this fails.
#
#   tools/android_sdk.sh 'ndk;28.2.13676358' 'system-images;android-34;default;x86_64'
set -euo pipefail

SDK=${ANDROID_HOME:?ANDROID_HOME must name the Android SDK}
for package in "$@"; do
  if [[ -z $package ]]; then
    echo "usage: tools/android_sdk.sh <sdkmanager package>..." >&2
    exit 2
  fi
  dir=$SDK/${package//;//}
  for attempt in 1 2; do
    # sdkmanager writes package.xml last; a package without it is partial
    [[ -f $dir/package.xml ]] && break
    # and so may be the download in .temp, which sdkmanager would resume
    rm -rf "$dir" "$SDK/.temp"
    "$SDK/cmdline-tools/latest/bin/sdkmanager" --install "$package" || echo "sdkmanager failed on $package" >&2
  done
  if [[ ! -f $dir/package.xml ]]; then
    echo "android_sdk.sh: $package is not installed after two downloads" >&2
    exit 1
  fi
done

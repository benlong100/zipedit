#!/bin/bash
# bootstrap.sh -- fetch and build everything the toolchain needs.
#
# The large binaries and disk images are deliberately not in git, so this
# script reconstructs them from scratch on a fresh clone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p tools vendor build

AC_VER=13.2
PRODOS_SHA=398d333cb2ab92df9f8bb2cf64b946f2567116910eb8359cf4bdee5d4194f0fa

echo "==> AppleCommander $AC_VER (native arm64; no JRE needed)"
if [ ! -e tools/ac ]; then
    for f in ac-darwin-arm64 acx-darwin-arm64; do
        curl -sL --fail -o "tools/$f.zip" \
            "https://github.com/AppleCommander/AppleCommander/releases/download/$AC_VER/$f.zip"
        unzip -oq "tools/$f.zip" -d tools/ && rm "tools/$f.zip"
    done
    ln -sf "ac-mac-aarch64-$AC_VER"  tools/ac
    ln -sf "acx-mac-aarch64-$AC_VER" tools/acx
fi
tools/ac -i /dev/null >/dev/null 2>&1 || true
echo "    ok"

echo "==> Merlin32 cross-assembler"
if [ ! -x tools/merlin32 ]; then
    [ -d vendor/merlin32 ] || \
        git clone -q --depth 1 https://github.com/apple2accumulator/merlin32.git vendor/merlin32
    make -C vendor/merlin32/Source >/dev/null
    cp vendor/merlin32/Source/merlin32 tools/
    mkdir -p tools/asminc
fi
echo "    ok ($(tools/merlin32 2>&1 | head -1))"

# NOTE: releases.prodos8.com is a custom domain on GitHub Pages that serves
# GitHub's *.github.io certificate, so HTTPS fails name validation. We fetch
# over HTTP from that same GitHub infrastructure and verify by SHA-256.
echo "==> ProDOS 2.4.3 system disk"
if [ ! -f vendor/ProDOS_2_4_3.po ]; then
    curl -sL --fail -o vendor/ProDOS_2_4_3.po http://releases.prodos8.com/ProDOS_2_4_3.po
fi
got=$(shasum -a 256 vendor/ProDOS_2_4_3.po | cut -d' ' -f1)
if [ "$got" != "$PRODOS_SHA" ]; then
    echo "    SHA-256 MISMATCH" >&2
    echo "    expected $PRODOS_SHA" >&2
    echo "    got      $got" >&2
    exit 1
fi
echo "    ok (sha256 verified)"

echo "==> Virtual ]["
if [ -d "/Applications/Virtual ][/Virtual ][.app" ]; then
    echo "    ok"
else
    echo "    NOT FOUND at /Applications/Virtual ][/ -- make run/test will fail" >&2
fi

echo
echo "bootstrap complete. try:  make run"

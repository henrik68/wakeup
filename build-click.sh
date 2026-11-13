#!/bin/bash
# Builds the OpenStore package (.click) with clickable (podman).
# The project path has spaces, which build tools dislike, so it is copied to ~/ut-apps first.
# WakeUp has a compiled part, so there is one .click per phone type (architecture):
#   bash build-click.sh              -> arm64 (Xperia XA2 and most phones)
#   bash build-click.sh arm64 armhf amd64   -> all three, for OpenStore
# The first build for an architecture downloads its build image (a few GB).
set -e
SRC="$(dirname "$(readlink -f "$0")")"
DST=~/ut-apps/wakeup-click
ARCHS="${*:-arm64}"
mkdir -p "$DST" "$SRC/out"
rsync -a --delete --exclude build --exclude out "$SRC"/ "$DST"/
cd "$DST"
bash update-translations.sh
for a in $ARCHS; do
  echo "===== building for $a"
  clickable build --arch "$a" 2>&1 | tee "build-$a.log"
  cp -v $(find build -path "*$a*" -name '*.click') "$SRC/out/"
done
ls -la "$SRC/out/"
echo "Done - .click files are in: $SRC/out/"

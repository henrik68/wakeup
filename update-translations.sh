#!/bin/bash
# Run after changing texts in the QML: updates po/wakeup.henrik68.pot, merges new texts into
# every po/<lang>.po (new ones stay untranslated = shown in English) and rebuilds the .mo files.
set -e
cd "$(dirname "$(readlink -f "$0")")"
xgettext --language=JavaScript --from-code=UTF-8 --keyword=tr --keyword=tr:1,2 --add-comments=TRANSLATORS \
  --package-name=wakeup.henrik68 --package-version="$(python3 -c 'import json;print(json.load(open("manifest.json.in"))["version"])')" \
  -o po/wakeup.henrik68.pot qml/*.qml
sed -i 's/charset=CHARSET/charset=UTF-8/' po/wakeup.henrik68.pot
for po in po/*.po; do
  lang=$(basename "$po" .po)
  msgmerge --quiet --update --backup=none "$po" po/wakeup.henrik68.pot
  mkdir -p "share/locale/$lang/LC_MESSAGES"
  msgfmt --check -o "share/locale/$lang/LC_MESSAGES/wakeup.henrik68.mo" "$po"
  echo "$lang: $(msgfmt --statistics -o /dev/null "$po" 2>&1)"
done

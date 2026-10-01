#!/bin/sh
set -eu
app=$(realpath "${1:?Pass the full path to the_list executable}")
case "$app" in *'"'*|*'%'*|*'\\'*) echo 'Unsupported executable path' >&2; exit 1;; esac
folder="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$folder"
cat > "$folder/app.thelist.the_list.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=The List
Exec="$app" %u
Terminal=false
MimeType=x-scheme-handler/thelist-capture;
Categories=Utility;
EOF
xdg-mime default app.thelist.the_list.desktop x-scheme-handler/thelist-capture
echo 'Browser capture registered.'

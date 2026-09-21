#!/bin/sh
set -eu
version="${DEV_UI_VERSION:-unknown}"
escaped_version="$(printf '%s' "$version" | sed 's/[&|\\]/\\&/g')"
mkdir -p /tmp/dev-ui-html
sed "s|__DEV_UI_VERSION__|$escaped_version|g" \
  /usr/share/nginx/html/index.html > /tmp/dev-ui-html/index.html
exec nginx -g 'daemon off;'

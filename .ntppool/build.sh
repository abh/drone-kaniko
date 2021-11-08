#!/bin/sh

set -euo pipefail

env | sort

VERSION=$(echo "${DRONE_TAG:-}" |sed 's/^v//g')
BUILD=${DRONE_BUILD_NUMBER:-dev}

if [[ -z "$VERSION" ]]; then
    VERSION="`git describe --abbrev=8`"
fi

VERSION=${VERSION}.${BUILD}

set -x

sed -i -E "s/^(DRONE_KANIKO_VERSION)=.*/\1=$VERSION/" plugin.sh

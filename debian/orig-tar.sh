#!/bin/sh -e

# $2 = version
# $3 = file

# Options
# -u force upstream release number
# --filter passed as tar --exclude option
# --filter-pristine-tar also filter pristine-tar
# --pristine-tar import pristine-tar delta

git-import-orig -u$2 --filter "*.jar" \
                --filter-pristine-tar --pristine-tar \
                $3


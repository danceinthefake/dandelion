#!/bin/sh
# A dandelion checkout only: copies the library (../mix.exs, ../lib) into
# vendor/dandelion, where the Docker build can see it (the build context is
# this directory). Run it before `docker compose … up --build`.
set -eu
cd "$(dirname "$0")/.."
rm -rf vendor/dandelion
mkdir -p vendor/dandelion
cp ../mix.exs vendor/dandelion/
cp -r ../lib vendor/dandelion/lib
echo "vendor/dandelion: $(find vendor/dandelion -name '*.ex' | wc -l) files"

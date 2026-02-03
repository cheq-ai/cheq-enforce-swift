#!/usr/bin/env -S dumb-init bash

function fatal() { error "$*"; exit $E_ERROR; }

function run() {
  xcodebuild test -scheme CheqEnforce -destination 'platform=iOS Simulator,name=iPhone 16' || fatal "failed to run tests on ios"
  xcodebuild test -scheme CheqEnforce -destination 'platform=visionOS Simulator,name=Apple Vision Pro' || fatal "failed to run tests on visionos"
  rm -rf docs-build
  xcodebuild docbuild -scheme CheqEnforce -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath docs-build || fatal "failed to build docs"
}

run "$@"

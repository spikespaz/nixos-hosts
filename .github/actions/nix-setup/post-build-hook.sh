#!/usr/bin/env bash
# Invoked by Nix after each successful build with $OUT_PATHS set to
# the space-separated list of newly-realized store paths. The
# cache-export step reads this log at end of job to decide what to
# copy into the local binary cache, skipping the full closure walk.
set -eu
if [ -n "${OUT_PATHS:-}" ]; then
  printf '%s\n' $OUT_PATHS >> /tmp/nix-built-paths.log
fi

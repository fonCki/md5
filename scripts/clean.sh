#!/usr/bin/env bash
set -euo pipefail
find techniques -type f -path "*/out/*" -not -name ".gitkeep" -delete

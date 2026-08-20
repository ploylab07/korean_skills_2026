#!/usr/bin/env bash
# Convenience wrapper: cd day1/003 && ./deploy.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/deploy.sh" "$@"

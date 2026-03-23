#!/bin/bash
set -euo pipefail

cat >&2 <<'EOF'
scripts/release.sh is deprecated.

Supported release flow:
1. Run `python3 scripts/prepare_release.py <version>`.
2. Commit the version file change using the emitted commit message.
3. Tag that commit as `v<version>` and push the tag.
4. GitHub Actions `.github/workflows/release.yml` publishes the release and updates `appcast.xml`.
EOF
exit 1

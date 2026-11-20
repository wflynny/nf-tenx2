#!/usr/bin/env bash
# ==============================================================================
# End-to-end tests with the real 10x tools, on the HPC.
#
# Writes input JSONs from the tiny test data inside each 10x install, runs each
# pipeline with the HPC profile, checks the published results, and refreshes
# the --help snapshots in test/cli-help/ for the same tool versions.
#
# Usage: bash test/e2e/run.sh <software root> [profile] [pipeline ...]
#   software root: folder holding <tool>/<version>/external (e.g. .../10x-genomics)
#   profile:       Nextflow profile (default elion2)
#   pipeline:      any of gex atac multiome visium (default: all found)
# Output goes to test/e2e/work/ (inputs, work dirs, results, logs).
# ==============================================================================
set -euo pipefail

[ $# -ge 1 ] || { sed -n '9,13p' "$0" >&2; exit 1; }
SOFTWARE_ROOT="$1"
PROFILE="${2:-elion2}"
shift $(( $# >= 2 ? 2 : 1 ))

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${HERE}/../.." && pwd)"
OUT="${HERE}/work"
rm -rf "${OUT}/inputs"
python3 "${HERE}/e2e.py" inputs --software-root "${SOFTWARE_ROOT}" --out "${OUT}/inputs"

pipelines=("$@")
if [ ${#pipelines[@]} -eq 0 ]; then
    for d in "${OUT}"/inputs/*/; do pipelines+=("$(basename "$d")"); done
fi

failed=0
for p in "${pipelines[@]}"; do
    echo "--- ${p}"
    rm -rf "${OUT}/results/${p}"
    if ! (cd "${OUT}" && nextflow run "${PROJECT_DIR}/main.nf" \
            -profile "${PROFILE}" \
            -work-dir "${OUT}/work-${p}" \
            --pipeline "${p}" \
            --input-dir "${OUT}/inputs/${p}" \
            --pubdir "${OUT}/results/${p}" \
            -ansi-log false) > "${OUT}/${p}.log" 2>&1; then
        echo "  run FAILED (see ${OUT}/${p}.log)"
        failed=1
    fi
done

# Check only the pipelines that ran.
rm -rf "${OUT}/check" && mkdir -p "${OUT}/check"
for p in "${pipelines[@]}"; do cp -r "${OUT}/inputs/${p}" "${OUT}/check/"; done
python3 "${HERE}/e2e.py" check --inputs "${OUT}/check" --results "${OUT}/results" || failed=1

# Refresh --help snapshots for every tool version that had inputs.
# shellcheck disable=SC2046  # one word per module
bash "${PROJECT_DIR}/test/cli-help/capture.sh" $(python3 "${HERE}/e2e.py" modules --inputs "${OUT}/check") || failed=1

exit ${failed}

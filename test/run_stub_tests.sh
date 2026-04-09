#!/usr/bin/env bash
# ==============================================================================
# Stub test runner for nf-tenx2
#
# Runs each pipeline entry point with -stub to validate:
#   - Channel wiring and branching logic
#   - Process input/output signatures
#   - File naming conventions
#
# Usage: bash test/run_stub_tests.sh [test_name]
#   If test_name is provided, runs only that test.
#   Otherwise runs all tests.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_INPUT_DIR="${SCRIPT_DIR}/input-jsons"
RESULTS_DIR="${SCRIPT_DIR}/results"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0

run_test() {
    local test_name="$1"
    local pipeline="$2"
    local input_json="$3"
    local work_dir="${SCRIPT_DIR}/work/${test_name}"

    echo -e "\n${YELLOW}━━━ TEST: ${test_name} ━━━${NC}"
    echo "  Pipeline: ${pipeline}"
    echo "  Input:    ${input_json}"

    rm -rf "${work_dir}" "${RESULTS_DIR}/${test_name}"
    mkdir -p "${work_dir}"

    if NXF_HOME="${work_dir}/.nxf_home" \
        NXF_LOG_FILE="${SCRIPT_DIR}/${test_name}.nextflow.log" \
        nextflow run "${PROJECT_DIR}/main.nf" \
        -profile testing \
        -stub \
        -work-dir "${work_dir}" \
        --pipeline "${pipeline}" \
        --inputJsonFiles "${input_json}" \
        --pubdir "${RESULTS_DIR}/${test_name}" \
        -ansi-log false \
        2>&1 | tee "${SCRIPT_DIR}/${test_name}.log"; then
        echo -e "  ${GREEN}✓ PASSED${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗ FAILED${NC} (see ${test_name}.log)"
        FAILED=$((FAILED + 1))
    fi
}

# ── Test definitions ─────────────────────────────────────────────────────────
# Format: "test_name|pipeline|input_json"
TESTS="
atac_count|atac|${TEST_INPUT_DIR}/atac_count.json
gex_count_ab|gex|${TEST_INPUT_DIR}/gex_count_ab.json
gex_count_simple|gex|${TEST_INPUT_DIR}/gex_count_simple.json
gex_multi_flex|gex|${TEST_INPUT_DIR}/gex_multi_flex.json
gex_multi_vdj|gex|${TEST_INPUT_DIR}/gex_multi_vdj.json
multiome_count|multiome|${TEST_INPUT_DIR}/multiome_count.json
visium_count|visium|${TEST_INPUT_DIR}/visium_count.json
xenium_relabel|xenium|${TEST_INPUT_DIR}/xenium_relabel.json
xenium_resegment|xenium|${TEST_INPUT_DIR}/xenium_resegment.json
"

# ── Run tests ────────────────────────────────────────────────────────────────
FILTER="${1:-}"

while IFS='|' read -r test_name pipeline input_json; do
    [ -z "$test_name" ] && continue
    if [ -n "$FILTER" ] && echo "$test_name" | grep -qv "$FILTER"; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    run_test "$test_name" "$pipeline" "$input_json"
done <<EOF
$(echo "$TESTS")
EOF

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}PASSED: ${PASSED}${NC}  ${RED}FAILED: ${FAILED}${NC}  SKIPPED: ${SKIPPED}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $FAILED

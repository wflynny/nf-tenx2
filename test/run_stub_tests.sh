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

    if nextflow run "${PROJECT_DIR}/main.nf" \
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
declare -A TESTS
TESTS[gex_count_simple]="gex|${TEST_INPUT_DIR}/gex_count_simple.json"
TESTS[gex_count_ab]="gex|${TEST_INPUT_DIR}/gex_count_ab.json"
TESTS[gex_multi_vdj]="gex|${TEST_INPUT_DIR}/gex_multi_vdj.json"
TESTS[gex_multi_flex]="gex|${TEST_INPUT_DIR}/gex_multi_flex.json"
TESTS[atac_count]="atac|${TEST_INPUT_DIR}/atac_count.json"
TESTS[multiome_count]="multiome|${TEST_INPUT_DIR}/multiome_count.json"
TESTS[visium_count]="visium|${TEST_INPUT_DIR}/visium_count.json"
TESTS[xenium_resegment]="xenium|${TEST_INPUT_DIR}/xenium_resegment.json"
TESTS[xenium_relabel]="xenium|${TEST_INPUT_DIR}/xenium_relabel.json"

# ── Run tests ────────────────────────────────────────────────────────────────
FILTER="${1:-}"

for test_name in $(echo "${!TESTS[@]}" | tr ' ' '\n' | sort); do
    if [[ -n "$FILTER" && "$test_name" != *"$FILTER"* ]]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    IFS='|' read -r pipeline input_json <<< "${TESTS[$test_name]}"
    run_test "$test_name" "$pipeline" "$input_json"
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}PASSED: ${PASSED}${NC}  ${RED}FAILED: ${FAILED}${NC}  SKIPPED: ${SKIPPED}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $FAILED

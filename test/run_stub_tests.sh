#!/usr/bin/env bash
# ==============================================================================
# Test runner for nf-tenx2
#
# Runs each pipeline with -stub to check channel wiring, branching and output
# file names. Then two real checks: RESOLVE_FASTQS on decoy files, and -resume.
#
# Usage: bash test/run_stub_tests.sh [name]   (substring match; default: all)
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

    echo -e "\n${YELLOW}--- TEST: ${test_name} ---${NC}"
    echo "  Pipeline: ${pipeline}"
    echo "  Input:    ${input_json}"

    rm -rf "${work_dir}" "${RESULTS_DIR}/${test_name}"
    mkdir -p "${work_dir}"

    # The pipeline reads <input-dir>/*.json, so give each test its own folder.
    local input_dir="${work_dir}/input"
    mkdir -p "${input_dir}"
    if [ -d "${input_json}" ]; then
        cp "${input_json}"/*.json "${input_dir}/"
    else
        cp "${input_json}" "${input_dir}/"
    fi

    if NXF_HOME="${work_dir}/.nxf_home" \
        NXF_LOG_FILE="${SCRIPT_DIR}/${test_name}.nextflow.log" \
        nextflow run "${PROJECT_DIR}/main.nf" \
        -profile testing \
        -stub \
        -work-dir "${work_dir}" \
        --pipeline "${pipeline}" \
        --input-dir "${input_dir}" \
        --pubdir "${RESULTS_DIR}/${test_name}" \
        -ansi-log false \
        2>&1 | tee "${SCRIPT_DIR}/${test_name}.log"; then
        echo -e "  ${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}FAILED${NC} (see ${test_name}.log)"
        FAILED=$((FAILED + 1))
    fi
}

# -- Test definitions ---------------------------------------------------------
# Format: "test_name|pipeline|input_json"
TESTS="
atac_count|atac|${TEST_INPUT_DIR}/atac_count.json
gex_count_ab|gex|${TEST_INPUT_DIR}/gex_count_ab.json
gex_count_simple|gex|${TEST_INPUT_DIR}/gex_count_simple.json
gex_count_topup|gex|${TEST_INPUT_DIR}/gex_count_topup.json
gex_multi_flex|gex|${TEST_INPUT_DIR}/gex_multi_flex.json
gex_multi_vdj|gex|${TEST_INPUT_DIR}/gex_multi_vdj.json
multiome_count|multiome|${TEST_INPUT_DIR}/multiome_count.json
visium_count|visium|${TEST_INPUT_DIR}/visium_count.json
xenium_relabel|xenium|${TEST_INPUT_DIR}/xenium_relabel.json
xenium_resegment|xenium|${TEST_INPUT_DIR}/xenium_resegment.json
gex_count_aggr|gex|${TEST_INPUT_DIR}/aggr
gex_multi_flex_v2|gex|${TEST_INPUT_DIR}/gex_multi_flex_v2.json
"

# -- Run tests ----------------------------------------------------------------
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

# -- RESOLVE_FASTQS real run (stubs skip its script) -------------------------
if [ -z "$FILTER" ] || echo "resolve_fastqs" | grep -q "$FILTER"; then
    echo -e "\n${YELLOW}--- TEST: resolve_fastqs (real run) ---${NC}"
    work_dir="${SCRIPT_DIR}/work/resolve_fastqs"
    rm -rf "${work_dir}" && mkdir -p "${work_dir}"
    if NXF_HOME="${work_dir}/.nxf_home" \
        NXF_LOG_FILE="${SCRIPT_DIR}/resolve_fastqs.nextflow.log" \
        nextflow run "${SCRIPT_DIR}/resolve_fastqs.nf" \
        -c "${PROJECT_DIR}/nextflow.config" \
        -profile testing \
        -work-dir "${work_dir}" \
        -ansi-log false \
        2>&1 | tee "${SCRIPT_DIR}/resolve_fastqs.log"; then
        echo -e "  ${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}FAILED${NC} (see resolve_fastqs.log)"
        FAILED=$((FAILED + 1))
    fi
else
    SKIPPED=$((SKIPPED + 1))
fi

# -- Duplicate dataset_id check -------------------------------------------------
# Two JSONs with one dataset_id must stop the run before any task starts.
if [ -z "$FILTER" ] || echo "duplicate_ids" | grep -q "$FILTER"; then
    echo -e "\n${YELLOW}--- TEST: duplicate_ids (expect failure) ---${NC}"
    work_dir="${SCRIPT_DIR}/work/duplicate_ids"
    rm -rf "${work_dir}" && mkdir -p "${work_dir}/input"
    cp "${TEST_INPUT_DIR}/gex_count_simple.json" "${work_dir}/input/a.json"
    cp "${TEST_INPUT_DIR}/gex_count_simple.json" "${work_dir}/input/b.json"
    if (cd "${work_dir}" && NXF_HOME="${work_dir}/.nxf_home" \
        nextflow run "${PROJECT_DIR}/main.nf" -profile testing -stub \
        --pipeline gex --input-dir "${work_dir}/input" \
        --pubdir "${work_dir}/results" -ansi-log false) > "${SCRIPT_DIR}/duplicate_ids.log" 2>&1; then
        echo -e "  ${RED}FAILED${NC} -- run succeeded with duplicate dataset_ids"
        FAILED=$((FAILED + 1))
    elif grep -q "appear in more than one input JSON" "${SCRIPT_DIR}/duplicate_ids.log"; then
        echo -e "  ${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}FAILED${NC} -- run failed for another reason (see duplicate_ids.log)"
        FAILED=$((FAILED + 1))
    fi
else
    SKIPPED=$((SKIPPED + 1))
fi

# -- Resume check --------------------------------------------------------------
# Runs one fixture twice with -resume. The second run may only redo
# CAPTURE_WORKFLOW and GENERATE_METADATA, which record the run's start time.
if [ -z "$FILTER" ] || echo "resume" | grep -q "$FILTER"; then
    echo -e "\n${YELLOW}--- TEST: resume ---${NC}"
    work_dir="${SCRIPT_DIR}/work/resume"
    rm -rf "${work_dir}" && mkdir -p "${work_dir}/input"
    cp "${TEST_INPUT_DIR}/gex_count_ab.json" "${work_dir}/input/"
    resume_run() {
        (cd "${work_dir}" && NXF_HOME="${work_dir}/.nxf_home" \
            nextflow run "${PROJECT_DIR}/main.nf" -profile testing -stub -resume \
            --pipeline gex --input-dir "${work_dir}/input" \
            --pubdir "${work_dir}/results" -ansi-log false)
    }
    if resume_run > "${SCRIPT_DIR}/resume.log" 2>&1 && resume_run >> "${SCRIPT_DIR}/resume.log" 2>&1; then
        statuses=$(cd "${work_dir}" && NXF_HOME="${work_dir}/.nxf_home" nextflow log last -f process,status)
        rerun=$(echo "$statuses" | grep -v 'CACHED$' | grep -vE ':(CAPTURE_WORKFLOW|GENERATE_METADATA)\b' || true)
        if [ -z "$rerun" ] && echo "$statuses" | grep -q 'CACHED$'; then
            echo -e "  ${GREEN}PASSED${NC} ($(echo "$statuses" | grep -c 'CACHED$') tasks cached)"
            PASSED=$((PASSED + 1))
        else
            echo -e "  ${RED}FAILED${NC} -- tasks re-ran on -resume:"
            echo "${rerun:-  (no cached tasks at all)}" | sed 's/^/    /'
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "  ${RED}FAILED${NC} (see resume.log)"
        FAILED=$((FAILED + 1))
    fi
else
    SKIPPED=$((SKIPPED + 1))
fi

# -- Summary ------------------------------------------------------------------
echo -e "\n----------------------------------------"
echo -e "  ${GREEN}PASSED: ${PASSED}${NC}  ${RED}FAILED: ${FAILED}${NC}  SKIPPED: ${SKIPPED}"
echo "----------------------------------------"

exit $FAILED

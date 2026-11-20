#!/usr/bin/env bash
# Save `<command> --help` for every command in bin/tenx_cli.json, for the given
# Lmod modules. test/unit/test_tenx_cli_help.py checks the rules against these.
# Run on the HPC, where the 10x modules exist, then commit the new .txt files.
#
# Usage: bash test/cli-help/capture.sh cellranger/9.0.1 spaceranger/3.1.1 ...
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="${HERE}/../../bin/tenx_cli.json"
TO_ASCII='tr/\x{201C}\x{201D}\x{2018}\x{2019}/""\x27\x27/; s/\x{2014}/--/g; s/\x{2013}/-/g; s/[^\x00-\x7F]//g'
[ $# -gt 0 ] || { echo "Usage: $0 <package>/<version> ..." >&2; exit 1; }

for mod in "$@"; do
    pkg="${mod%%/*}"
    version="${mod#*/}"
    module purge
    module load "${mod}"
    # One "<rules name> <command words...>" line per command run by this package.
    python3 -c '
import json, sys
for name, spec in json.load(open(sys.argv[1])).items():
    if spec["command"][0] == sys.argv[2]:
        print(name, *spec["command"])
' "${RULES}" "${pkg}" | while read -r name cmd; do
        out="${HERE}/${name}@${version}.txt"
        # Keep snapshots ASCII: curly quotes to plain ones, em dash to "--".
        # shellcheck disable=SC2086  # cmd is "<tool> <subcommand>"
        NO_COLOR=1 ${cmd} --help 2>&1 | perl -CSD -pe "${TO_ASCII}" > "${out}" || true
        if [ -s "${out}" ]; then
            echo "wrote ${out}"
        else
            echo "no help output for ${cmd} ${version}" >&2
            rm -f "${out}"
        fi
    done
done

/*
 * Collect metric files from a *ranger output directory into a single JSON.
 *
 * Tool-agnostic: collect_metrics.py just traverses the directory for metric
 * file patterns, so one process serves every assay (mirrors MD5SUM). Runs in
 * parallel with the per-assay tool output hashing.
 */
process COLLECT_METRICS {
    label 'process_single'

    input:
        tuple val(record), path(result_dir)

    output:
        tuple val(record), path("collected_metrics.json"), emit: metrics

    script:
    """
    collect_metrics.py --tool-dir ${result_dir} --out collected_metrics.json
    """

    stub:
    """
    echo '{}' > collected_metrics.json
    """
}

/**
 * Version-aware command builder for 10x Genomics tools.
 *
 * Each *ranger tool has version-dependent CLI syntax. This class centralizes
 * all that logic so process definitions stay clean.
 *
 * Verified version breaks (from 10x official release notes):
 *
 * cellranger count/multi:
 *   7.0:  --include-introns added. Flex support via multi + probe-set.
 *   7.x:  --no-bam (optional flag to suppress BAM output)
 *   8.0:  --no-bam replaced by --create-bam true|false (REQUIRED)
 *   9.0:  OCM support, antibody hashtag analysis, cellranger annotate
 *   10.0: Flex v2 (384-plex), mkfastq deprecated, multi output restructured
 *
 * cellranger-arc count:
 *   2.0.x: no --create-bam flag
 *   2.1.0: --create-bam true|false (REQUIRED)
 *
 * cellranger-atac count:
 *   2.1.0+: no CLI breaking changes. --id/--reference/--fastqs/--sample stable.
 *           Always produces BAM (no create-bam flag).
 *
 * spaceranger count:
 *   2.0+:  --cytaimage for CytAssist images
 *   3.0:   --create-bam true|false (REQUIRED). --slide/--area optional with CytAssist.
 *   4.0:   --probe-set not needed for Visium HD 3'. Cell segmentation support.
 *
 * xeniumranger resegment/relabel:
 *   3.0+: stable CLI for core args (--xenium-bundle, --id, --localcores, --localmem)
 *         --resegment-nuclei deprecated in resegment (always resegments now)
 *   4.0:  protein quantification support (new optional args only)
 *
 * Minimum supported versions:
 *   cellranger:       7.0.0
 *   cellranger-arc:   2.0.1
 *   cellranger-atac:  2.1.0
 *   spaceranger:      3.0.0
 *   xeniumranger:     3.0.0
 */
class CommandBuilder {

    // ─── Version comparison ─────────────────────────────────────────

    /**
     * Parse "major.minor.patch" into a list of ints [major, minor, patch].
     */
    static List<Integer> parseVersion(String version) {
        def parts = version.tokenize('.')
        return parts.collect { tok -> tok.replaceAll('[^0-9]', '').toInteger() }
    }

    /**
     * True if version >= threshold.
     */
    static boolean versionGte(String version, String threshold) {
        def v = parseVersion(version)
        def t = parseVersion(threshold)
        for (int i = 0; i < Math.max(v.size(), t.size()); i++) {
            def vi = i < v.size() ? v[i] : 0
            def ti = i < t.size() ? t[i] : 0
            if (vi > ti) return true
            if (vi < ti) return false
        }
        return true  // equal
    }

    // ─── Common helpers ─────────────────────────────────────────────

    /**
     * Get a value from the record's gene-expression section, with a default.
     * Strips inline comments (e.g. "false #do not generate BAM" -> "false").
     */
    static String gexParam(Map record, String key, String defaultValue) {
        def gex = record.get('gene-expression')
        if (gex == null) return defaultValue
        def val = gex.get(key)
        if (val == null || val.toString().trim().isEmpty()) return defaultValue
        return val.toString().split('#')[0].trim()
    }

    // ─── cellranger count ───────────────────────────────────────────

    static String cellrangerCount(Map record, int cpus, long localmem) {
        def version   = record.pipeline.tool_version
        def datasetId = record.pipeline.dataset_id
        def reference = record['gene-expression'].reference

        def cmd = []
        cmd << "cellranger count"
        cmd << "    --id ${datasetId}"
        cmd << "    --transcriptome ${reference}"
        cmd << "    --libraries libraries.csv"

        // BAM generation
        if (versionGte(version, '8.0.0')) {
            def createBam = gexParam(record, 'create-bam', 'false')
            cmd << "    --create-bam ${createBam}"
        } else {
            def createBam = gexParam(record, 'create-bam', 'false')
            if (createBam == 'false') {
                cmd << "    --no-bam"
            }
        }

        // Introns
        if (versionGte(version, '7.0.0')) {
            def includeIntrons = gexParam(record, 'include-introns', 'true')
            cmd << "    --include-introns ${includeIntrons}"
        }

        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"

        return cmd.join(' \\\n')
    }

    // ─── cellranger multi ───────────────────────────────────────────

    static String cellrangerMulti(Map record, int cpus, long localmem) {
        def version   = record.pipeline.tool_version
        def datasetId = record.pipeline.dataset_id

        def cmd = []
        cmd << "cellranger multi"
        cmd << "    --id ${datasetId}"
        cmd << "    --csv multi.csv"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"

        return cmd.join(' \\\n')
    }

    // ─── cellranger-arc count ───────────────────────────────────────

    static String cellrangerArcCount(Map record, int cpus, long localmem) {
        def version   = record.pipeline.tool_version
        def datasetId = record.pipeline.dataset_id
        def reference = record['multiome'].reference

        def cmd = []
        cmd << "cellranger-arc count"
        cmd << "    --id ${datasetId}"
        cmd << "    --reference ${reference}"
        cmd << "    --libraries libraries.csv"

        // BAM generation: >= 2.1.0 uses --create-bam, older uses --no-bam
        if (versionGte(version, '2.1.0')) {
            def createBam = gexParam(record, 'create-bam', 'true')
            cmd << "    --create-bam ${createBam}"
        }
        // Pre-2.1.0: BAM is always created (no opt-out flag that's mandatory)

        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"

        return cmd.join(' \\\n')
    }

    // ─── cellranger-atac count ──────────────────────────────────────

    static String cellrangerAtacCount(Map record, int cpus, long localmem) {
        def version   = record.pipeline.tool_version
        def datasetId = record.pipeline.dataset_id
        def reference = record['atac'].reference
        def libraries = record.libraries
        def fastqDirs = libraries.collect { lib -> lib.fastqs }.unique().join(',')
        def samples   = libraries.collect { lib -> lib.sample }.unique().join(',')

        def cmd = []
        cmd << "cellranger-atac count"
        cmd << "    --id ${datasetId}"
        cmd << "    --reference ${reference}"
        cmd << "    --fastqs ${fastqDirs}"
        cmd << "    --sample ${samples}"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"

        return cmd.join(' \\\n')
    }

    // ─── spaceranger count ──────────────────────────────────────────
    //
    // Version breaks:
    //   >= 2.0: --cytaimage for CytAssist images
    //   >= 3.0: --create-bam true|false REQUIRED
    //           --slide and --area optional if CytAssist image has metadata
    //   >= 4.0: --probe-set NOT needed for Visium HD 3' (auto-detected)
    //           cell segmentation support (--custom-segmentation-file)
    //
    static String spacerangerCount(Map record, int cpus, long localmem) {
        def version   = record.pipeline.tool_version
        def datasetId = record.pipeline.dataset_id
        def reference = record['gene-expression'].reference
        def libraries = record.libraries
        def fastqDirs = libraries.collect { lib -> lib.fastqs }.unique().join(',')
        def samples   = libraries.collect { lib -> lib.sample }.unique().join(',')
        def spatial   = record.get('spatial', [:])

        def cmd = []
        cmd << "spaceranger count"
        cmd << "    --id ${datasetId}"
        cmd << "    --transcriptome ${reference}"
        cmd << "    --fastqs ${fastqDirs}"
        cmd << "    --sample ${samples}"

        // --create-bam: required starting from SR 3.0
        if (versionGte(version, '3.0.0')) {
            def createBam = gexParam(record, 'create-bam', 'true')
            cmd << "    --create-bam ${createBam}"
        }

        // Probe set: needed for FFPE/Visium HD on SR < 4.0
        // On SR >= 4.0, Visium HD 3' auto-detects (user should omit probe-set)
        def probeSet = gexParam(record, 'probe-set', null)
        if (probeSet) {
            cmd << "    --probe-set ${probeSet}"
        }

        // Spatial: slide and area
        if (spatial.slide) cmd << "    --slide ${spatial.slide}"
        if (spatial.area)  cmd << "    --area ${spatial.area}"

        // Image inputs: --cytaimage available from SR 2.0+
        if (spatial.cytaimage) {
            cmd << "    --cytaimage ${spatial.cytaimage}"
        }
        if (spatial.darkimage) {
            cmd << "    --darkimage ${spatial.darkimage}"
        }
        if (spatial.image) {
            cmd << "    --image ${spatial.image}"
        }

        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"

        return cmd.join(' \\\n')
    }

    // ─── cellranger aggr ─────────────────────────────────────────────

    static String cellrangerAggr(String aggrId, int cpus, long localmem) {
        def cmd = []
        cmd << "cellranger aggr"
        cmd << "    --id ${aggrId}"
        cmd << "    --csv aggr.csv"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"
        return cmd.join(' \\\n')
    }

    // ─── cellranger-atac aggr ──────────────────────────────────────

    static String cellrangerAtacAggr(String aggrId, String reference, int cpus, long localmem) {
        def cmd = []
        cmd << "cellranger-atac aggr"
        cmd << "    --id ${aggrId}"
        cmd << "    --csv aggr.csv"
        cmd << "    --reference ${reference}"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"
        return cmd.join(' \\\n')
    }

    // ─── cellranger-arc aggr ───────────────────────────────────────

    static String cellrangerArcAggr(String aggrId, String reference, int cpus, long localmem) {
        def cmd = []
        cmd << "cellranger-arc aggr"
        cmd << "    --id ${aggrId}"
        cmd << "    --csv aggr.csv"
        cmd << "    --reference ${reference}"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"
        return cmd.join(' \\\n')
    }

    // ─── spaceranger aggr ──────────────────────────────────────────

    static String spacerangerAggr(String aggrId, int cpus, long localmem) {
        def cmd = []
        cmd << "spaceranger aggr"
        cmd << "    --id ${aggrId}"
        cmd << "    --csv aggr.csv"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"
        cmd << "    --disable-ui"
        return cmd.join(' \\\n')
    }

    // ─── xeniumranger resegment ─────────────────────────────────────

    static String xeniumrangerResegment(Map record, int cpus, long localmem) {
        def version    = record.pipeline.tool_version
        def datasetId  = record.pipeline.dataset_id
        def xeniumPath = record.xenium.input_path

        def cmd = []
        cmd << "xeniumranger resegment"
        cmd << "    --id ${datasetId}"
        cmd << "    --xenium-bundle ${xeniumPath}"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"

        return cmd.join(' \\\n')
    }

    // ─── xeniumranger relabel ───────────────────────────────────────

    static String xeniumrangerRelabel(Map record, int cpus, long localmem) {
        def version    = record.pipeline.tool_version
        def datasetId  = record.pipeline.dataset_id
        def xeniumPath = record.xenium.input_path
        def panel      = record.xenium.get('panel')

        def cmd = []
        cmd << "xeniumranger relabel"
        cmd << "    --id ${datasetId}"
        cmd << "    --xenium-bundle ${xeniumPath}"
        if (panel) cmd << "    --panel ${panel}"
        cmd << "    --localcores ${cpus}"
        cmd << "    --localmem ${localmem}"

        return cmd.join(' \\\n')
    }
}

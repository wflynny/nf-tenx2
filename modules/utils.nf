/*
 * Helper functions shared by modules and workflows.
 */

/**
 * Calculate --localmem value for 10x tools from task.memory.
 * Returns 95% of available memory in GB, with a fallback default
 * if task.memory is null (e.g. no profile loaded).
 */
def calc_localmem(task_memory, fallback_gb = 64) {
    if (task_memory == null) return fallback_gb
    return Math.round(task_memory.toGiga() * 0.95)
}

/**
 * Build a JSON string capturing Nextflow workflow provenance.
 * Called in workflow blocks where the workflow object is accessible.
 */
def capture_workflow_json(pipeline_version) {
    def wf_info = [
        pipeline_name:    "nf-tenx2",
        pipeline_version: pipeline_version,
        nextflow_version: nextflow.version.toString(),
        profile:          workflow.profile.toString(),
        command_line:      workflow.commandLine.toString(),
        run_name:          workflow.runName.toString(),
        session_id:        workflow.sessionId.toString(),
        start:             workflow.start.toString(),
        script_id:         workflow.scriptId.toString(),
        work_dir:          workflow.workDir.toString(),
        launch_dir:        workflow.launchDir.toString(),
        user_name:         workflow.userName.toString(),
    ]
    return groovy.json.JsonOutput.prettyPrint(
        groovy.json.JsonOutput.toJson(wf_info)
    )
}

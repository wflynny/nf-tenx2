workflow COMPLETE {
    main:
        // Hook for any final aggregation or notification logic.
        // Currently a no-op; extend as needed (e.g., email, Slack webhook).
        log.info "Pipeline complete."
}

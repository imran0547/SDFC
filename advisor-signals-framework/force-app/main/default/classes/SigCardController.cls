/**
 * Apex endpoints for the signal card components on the record page and in the agent panel.
 * Every method runs as the advisor. Nothing is saved except the advisor's own response.
 */
public with sharing class SigCardController {
    @AuraEnabled
    public static List<SigInsight> getInsights(
        Id recordId,
        String agent,
        String surface,
        Boolean explicitAsk,
        String sessionToken
    ) {
        try {
            String normalizedSurface = surface == SigEngine.SURFACE_AGENT ? SigEngine.SURFACE_AGENT : SigEngine.SURFACE_RECORD_PAGE;
            return SigEngine.evaluate(recordId, agent, normalizedSurface, explicitAsk == true, sessionToken);
        } catch (Exception e) {
            SigLog.error(null, recordId, 'Signals could not be read.', e);
            throw friendly('I can\'t check this record right now. Please try again shortly.');
        }
    }

    @AuraEnabled
    public static void recordResponse(
        String insightJson,
        String status,
        String surface,
        String sessionToken,
        Id createdRecordId
    ) {
        try {
            SigInsight ins = (SigInsight) JSON.deserialize(insightJson, SigInsight.class);
            SigResponseService.record(ins, status, surface, sessionToken, createdRecordId);
        } catch (Exception e) {
            SigLog.error(null, createdRecordId, 'Response could not be saved.', e);
            throw friendly('I couldn\'t save your response. Nothing else was changed.');
        }
    }

    /** Called just before a save: true when the signal still applies. */
    @AuraEnabled
    public static Boolean recheck(Id recordId, String responseKey) {
        try {
            return SigEngine.recheck(recordId, responseKey);
        } catch (Exception e) {
            SigLog.error(null, recordId, 'Recheck failed.', e);
            throw friendly('I can\'t confirm this signal right now. Nothing has been saved.');
        }
    }

    @AuraEnabled
    public static Map<String, Object> getTaskDefaults(String insightJson, Id whatId) {
        try {
            SigInsight ins = String.isBlank(insightJson) ? null : (SigInsight) JSON.deserialize(insightJson, SigInsight.class);
            return SigFollowUpService.taskDefaults(ins, whatId);
        } catch (Exception e) {
            SigLog.error(null, whatId, 'Task defaults could not be prepared.', e);
            throw friendly('I can\'t prepare the Task right now. You can create it manually.');
        }
    }

    /** Lets the components log a failed save, so failures are visible to admins. */
    @AuraEnabled
    public static void logClientError(String signalKey, Id recordId, String message) {
        SigLog.warn(signalKey, recordId, message == null ? 'Client-side error.' : message.left(32000));
    }

    private static AuraHandledException friendly(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}

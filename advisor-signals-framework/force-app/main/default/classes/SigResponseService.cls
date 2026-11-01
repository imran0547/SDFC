/**
 * Stores and applies advisors' responses to signals.
 *
 * Signals are computed live; only responses are stored, one row per advisor per signal
 * instance. Because the user Id is part of the response key, one advisor's Not now
 * never hides a signal from another advisor, and new evidence gives a new key and so a
 * fresh signal.
 */
public with sharing class SigResponseService {
    public static final String NOT_NOW = 'Not Now';
    public static final String ACTED_ON = 'Acted On';

    /** agent | signal | anchor | evidence | user */
    public static String buildKey(String agent, String signalKey, Id anchorId, String evidenceKey, Id userId) {
        String key = String.join(
            new List<String>{
                agent == null ? '' : agent,
                signalKey == null ? '' : signalKey,
                String.valueOf(anchorId),
                String.isBlank(evidenceKey) ? 'none' : evidenceKey,
                String.valueOf(userId)
            },
            '|'
        );
        if (key.length() > 255) {
            // Keep the user Id at the end so ownership can always be checked.
            String userPart = '|' + String.valueOf(userId);
            key = key.left(255 - userPart.length()) + userPart;
        }
        return key;
    }

    /**
     * Removes or annotates insights the running user has already responded to.
     * - Acted On: never shown again.
     * - Not Now with Resurface Days > 0: hidden until the wait has passed.
     * - Not Now with Resurface Days = 0: hidden for the rest of the same browser session.
     * - While hidden, an explicit request still shows it when Show On Ask is checked.
     * - Whenever a skipped insight is shown, a reminder line gives the skipped-on date.
     */
    public static List<SigInsight> apply(
        List<SigInsight> insights,
        Map<String, Signal_Definition__mdt> definitionsByKey,
        Boolean explicitAsk,
        String sessionToken
    ) {
        if (insights == null || insights.isEmpty()) {
            return new List<SigInsight>();
        }
        Set<String> keys = new Set<String>();
        for (SigInsight ins : insights) {
            keys.add(ins.responseKey);
        }
        Id userId = UserInfo.getUserId();
        Map<String, Signal_Response__c> byKey = new Map<String, Signal_Response__c>();
        for (Signal_Response__c r : [
            SELECT Response_Key__c, Status__c, Responded_At__c, Session_Token__c
            FROM Signal_Response__c
            WHERE Responded_By__c = :userId AND Response_Key__c IN :keys
            WITH USER_MODE
        ]) {
            byKey.put(r.Response_Key__c, r);
        }

        List<SigInsight> visible = new List<SigInsight>();
        Datetime now = SigClock.now();
        for (SigInsight ins : insights) {
            Signal_Response__c r = byKey.get(ins.responseKey);
            if (r == null) {
                visible.add(ins);
                continue;
            }
            if (r.Status__c == ACTED_ON) {
                continue;
            }
            Signal_Definition__mdt def = definitionsByKey == null ? null : definitionsByKey.get(ins.signalKey);
            Integer waitDays = (def == null || def.Resurface_Days__c == null) ? 0 : def.Resurface_Days__c.intValue();
            Boolean showOnAsk = def != null && def.Show_On_Ask__c == true;
            Boolean hidden;
            if (waitDays > 0) {
                hidden = r.Responded_At__c != null && r.Responded_At__c.addDays(waitDays) > now;
            } else {
                hidden = String.isNotBlank(sessionToken) && sessionToken == r.Session_Token__c;
            }
            if (hidden && !(explicitAsk == true && showOnAsk)) {
                continue;
            }
            if (r.Responded_At__c != null) {
                ins.reminderText = 'You skipped this on ' + r.Responded_At__c.date().format() + '.';
            }
            visible.add(ins);
        }
        return visible;
    }

    /** Saves the running user's response. Only the user's own response key is accepted. */
    public static Signal_Response__c record(
        SigInsight ins,
        String status,
        String surface,
        String sessionToken,
        Id createdRecordId
    ) {
        if (ins == null || String.isBlank(ins.responseKey)) {
            throw new SigException('The signal to respond to is missing.');
        }
        if (status != NOT_NOW && status != ACTED_ON) {
            throw new SigException('Unknown response status: ' + status);
        }
        if (!ins.responseKey.endsWith('|' + UserInfo.getUserId())) {
            throw new SigException('A response can only be recorded by the advisor it belongs to.');
        }
        Id clientId = toId(ins.clientId);
        Id opportunityId = toId(ins.opportunityId);
        Id anchorId = opportunityId != null ? opportunityId : (clientId != null ? clientId : toId(ins.anchorId));
        if (!SigAccess.canRead(anchorId)) {
            throw new SigException('You do not have access to this record.');
        }
        if (status == ACTED_ON && createdRecordId != null && createdRecordId.getSObjectType() == Opportunity.SObjectType) {
            opportunityId = createdRecordId;
        }
        if (clientId == null && opportunityId == null && anchorId != null) {
            if (anchorId.getSObjectType() == Account.SObjectType) {
                clientId = anchorId;
            } else if (anchorId.getSObjectType() == Opportunity.SObjectType) {
                opportunityId = anchorId;
            }
        }
        Signal_Response__c r = new Signal_Response__c(
            Response_Key__c = ins.responseKey,
            Signal_Key__c = ins.signalKey,
            Status__c = status,
            Client__c = clientId,
            Opportunity__c = opportunityId,
            Responded_By__c = UserInfo.getUserId(),
            Responded_At__c = SigClock.now(),
            Change_Type__c = ins.changeType == null ? null : ins.changeType.left(80),
            Evidence_Date__c = ins.evidenceDate,
            Surface__c = surface == 'Agent' ? 'Agent' : 'Record Page',
            Prompt__c = ins.prompt == null ? null : ins.prompt.left(1000),
            Priority__c = ins.priority == 'High' ? 'High' : 'Normal',
            Session_Token__c = sessionToken == null ? null : sessionToken.left(64),
            Created_Record_Id__c = createdRecordId
        );
        Database.upsert(r, Signal_Response__c.Response_Key__c, true, AccessLevel.USER_MODE);
        return r;
    }

    public static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }
}

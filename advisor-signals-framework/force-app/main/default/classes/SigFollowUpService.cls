/**
 * Suggested values for a follow-up Task. The values pre-fill a form; the advisor saves it.
 * The Task description repeats only what the card showed and never adds personal details.
 */
public with sharing class SigFollowUpService {
    /** A signal to follow up on, and the record the follow-up relates to. */
    public class Resolved {
        public SigInsight insight;
        public Id whatId;
    }

    /**
     * Finds the signal behind a response key. After the advisor acted, the live signal is
     * usually gone (an Opportunity now exists), so the stored response is used first; before
     * that, the live signal is used.
     */
    public static Resolved resolve(Id recordId, String responseKey) {
        if (String.isBlank(responseKey)) {
            return null;
        }
        Id userId = UserInfo.getUserId();
        List<Signal_Response__c> rows = [
            SELECT Signal_Key__c, Change_Type__c, Prompt__c, Client__c, Opportunity__c, Created_Record_Id__c, Evidence_Date__c, Response_Key__c
            FROM Signal_Response__c
            WHERE Response_Key__c = :responseKey AND Responded_By__c = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        Resolved result = new Resolved();
        if (!rows.isEmpty()) {
            Signal_Response__c r = rows[0];
            SigInsight ins = new SigInsight();
            ins.responseKey = r.Response_Key__c;
            ins.signalKey = r.Signal_Key__c;
            ins.changeType = r.Change_Type__c;
            ins.prompt = r.Prompt__c;
            ins.clientId = r.Client__c;
            ins.opportunityId = r.Opportunity__c;
            ins.evidenceDate = r.Evidence_Date__c;
            Signal_Definition__mdt def = SigConfig.definition(r.Signal_Key__c);
            ins.allowTask = def != null && def.Allow_Task__c == true;
            Id created = SigResponseService.toId(r.Created_Record_Id__c);
            result.whatId = created != null ? created : (r.Opportunity__c != null ? r.Opportunity__c : r.Client__c);
            if (result.whatId != null && result.whatId.getSObjectType() == Opportunity.SObjectType) {
                for (Opportunity o : [SELECT Name FROM Opportunity WHERE Id = :result.whatId WITH USER_MODE LIMIT 1]) {
                    ins.suggestedValues.put('Name', o.Name);
                }
            }
            result.insight = ins;
            return result;
        }
        SigInsight live = SigEngine.findInsight(recordId, responseKey);
        if (live == null) {
            return null;
        }
        result.insight = live;
        Id opportunityId = SigResponseService.toId(live.opportunityId);
        result.whatId = opportunityId != null ? opportunityId : SigResponseService.toId(live.clientId);
        return result;
    }

    public static Map<String, Object> taskDefaults(SigInsight ins, Id whatId) {
        Map<String, Object> values = new Map<String, Object>();
        Signal_Definition__mdt def = ins == null ? null : SigConfig.definition(ins.signalKey);

        String subject = null;
        if (ins != null && ins.suggestedValues != null && ins.suggestedValues.get('Name') != null) {
            subject = String.valueOf(ins.suggestedValues.get('Name'));
        } else if (ins != null && String.isNotBlank(ins.changeType)) {
            subject = 'Follow up: ' + ins.changeType;
        }
        if (subject != null) {
            values.put('Subject', subject.left(255));
        }

        Integer dueDays = (def == null || def.Task_Due_Business_Days__c == null) ? 2 : def.Task_Due_Business_Days__c.intValue();
        values.put('ActivityDate', SigDates.addBusinessDays(SigClock.today(), dueDays));
        if (def != null && String.isNotBlank(def.Task_Priority__c)) {
            values.put('Priority', def.Task_Priority__c);
        }
        values.put('OwnerId', UserInfo.getUserId());
        if (whatId != null) {
            values.put('WhatId', whatId);
        }

        Id clientId = ins == null ? null : SigResponseService.toId(ins.clientId);
        if (clientId != null) {
            SigRecordInfo info = SigRecordInfo.load(clientId);
            if (info != null && info.personContactId != null) {
                values.put('WhoId', info.personContactId);
            }
        }

        if (ins != null) {
            List<String> lines = new List<String>();
            if (String.isNotBlank(ins.prompt)) {
                lines.add(ins.prompt);
            }
            if (String.isNotBlank(ins.source) || ins.evidenceDate != null) {
                lines.add('Source: ' + (ins.source == null ? '' : ins.source) + (ins.evidenceDate == null ? '' : ', ' + ins.evidenceDate.format()));
            }
            Object nextStep = ins.suggestedValues == null ? null : ins.suggestedValues.get('NextStep');
            if (nextStep != null) {
                lines.add('Next step: ' + String.valueOf(nextStep));
            }
            if (!lines.isEmpty()) {
                values.put('Description', String.join(lines, '\n').left(32000));
            }
        }
        return values;
    }
}

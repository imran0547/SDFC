/**
 * Suggested values for a follow-up Task. The values pre-fill a form; the advisor saves it.
 * The Task description repeats only what the card showed and never adds personal details.
 */
public with sharing class SigFollowUpService {
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

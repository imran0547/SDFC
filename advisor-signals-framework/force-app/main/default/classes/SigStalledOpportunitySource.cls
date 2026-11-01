/**
 * Sample Next Best Action source: an open Opportunity that has stayed in its current
 * stage for at least the configured number of days.
 *
 * Parameters (Signal_Parameter__mdt), scoped by Opportunity record type and stage:
 *   Threshold_Days          Integer  days in stage that count as stalled (sort parameter)
 *   Next_Stage              Stage    suggested next stage; must be open and active
 *   Close_Date_Offset_Days  Integer  suggested Close Date = today + offset
 *   Default_Next_Step       Text     suggested Next Step
 *   Comparison              Text     GreaterOrEqual (default) or Greater
 */
public with sharing class SigStalledOpportunitySource implements SigSource {
    public List<SigInsight> evaluate(SigContext ctx) {
        List<SigInsight> out = new List<SigInsight>();
        if (ctx.recordId.getSObjectType() != Opportunity.SObjectType) {
            return out;
        }
        Boolean hasRecordType = Schema.SObjectType.Opportunity.fields.getMap().containsKey('recordtypeid');
        String soql =
            'SELECT Id, Name, StageName, IsClosed, CloseDate, NextStep, AccountId, CreatedDate, LastStageChangeDate, LastStageChangeInDays' +
            (hasRecordType ? ', RecordType.DeveloperName' : '') +
            ' FROM Opportunity WHERE Id = :recordId';
        List<SObject> rows = Database.queryWithBinds(soql, new Map<String, Object>{ 'recordId' => ctx.recordId }, AccessLevel.USER_MODE);
        if (rows.isEmpty()) {
            return out;
        }
        Opportunity opp = (Opportunity) rows[0];
        if (opp.IsClosed) {
            return out;
        }
        String recordType = null;
        if (hasRecordType && opp.getSObject('RecordType') != null) {
            recordType = (String) opp.getSObject('RecordType').get('DeveloperName');
        }

        SigConfig.Rule rule = ctx.rule(recordType, opp.StageName, null);
        Integer threshold = rule.getInteger('Threshold_Days');
        if (threshold == null) {
            return out; // no rule configured for this record type and stage
        }
        Integer days = daysInStage(opp, ctx.today);
        if (days == null) {
            SigLog.warn(ctx.signalKey(), opp.Id, 'Days in stage could not be determined.');
            return out;
        }
        String comparison = rule.has('Comparison') ? rule.getText('Comparison') : 'GreaterOrEqual';
        Boolean stalled = comparison.equalsIgnoreCase('Greater') ? days > threshold : days >= threshold;
        if (!stalled) {
            return out;
        }

        Date entered = stageEntryDate(opp);
        SigInsight ins = ctx.newInsight();
        ins.opportunityId = opp.Id;
        ins.clientId = opp.AccountId;
        ins.changeType = 'Stalled Stage';
        ins.dedupeGroup = 'stalled';
        ins.evidenceDate = entered;
        ins.evidenceId = opp.Id + ':' + opp.StageName + ':' + String.valueOf(entered);
        ins.source = 'Days in stage';
        ins.confidence = 'Confirmed';
        ins.tokens.put('OpportunityName', opp.Name);
        ins.tokens.put('Stage', opp.StageName);
        ins.tokens.put('Days', String.valueOf(days));
        ins.tokens.put('Threshold', String.valueOf(threshold));

        String nextStage = SigOpportunityDefaults.openStage(rule.getText('Next_Stage'));
        if (nextStage != null) {
            ins.suggestedValues.put('StageName', nextStage);
        } else {
            ins.notSuggested.add('Stage');
        }
        Integer offset = rule.getInteger('Close_Date_Offset_Days');
        if (offset != null) {
            ins.suggestedValues.put('CloseDate', ctx.today.addDays(offset));
        } else {
            ins.notSuggested.add('Close Date');
        }
        if (rule.has('Default_Next_Step')) {
            ins.suggestedValues.put('NextStep', rule.getText('Default_Next_Step').left(255));
        } else {
            ins.notSuggested.add('Next Step');
        }
        out.add(ins);
        return out;
    }

    @TestVisible
    static Integer daysInStage(Opportunity opp, Date today) {
        Object inDays = opp.get('LastStageChangeInDays');
        if (inDays != null) {
            return Integer.valueOf(inDays);
        }
        Date entered = stageEntryDate(opp);
        return entered == null ? null : entered.daysBetween(today);
    }

    private static Date stageEntryDate(Opportunity opp) {
        Object changed = opp.get('LastStageChangeDate');
        if (changed != null) {
            return ((Datetime) changed).date();
        }
        return opp.CreatedDate == null ? null : opp.CreatedDate.date();
    }
}

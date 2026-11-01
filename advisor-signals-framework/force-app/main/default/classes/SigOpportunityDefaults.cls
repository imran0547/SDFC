/**
 * Suggested values for a drafted Opportunity, from the signal definition.
 * Nothing is guessed: a value that cannot be grounded is left out and listed in
 * notSuggested so the card can tell the advisor.
 */
public with sharing class SigOpportunityDefaults {
    public static void apply(SigInsight ins, Signal_Definition__mdt def, SigRecordInfo info) {
        Map<String, Object> values = ins.suggestedValues;

        if (info != null && info.clientId != null && !values.containsKey('AccountId')) {
            values.put('AccountId', info.clientId);
        }

        Schema.RecordTypeInfo rti = recordTypeInfo(def.Opportunity_Record_Type__c);
        if (rti != null) {
            values.put('RecordTypeId', rti.getRecordTypeId());
            ins.tokens.put('RecordType', rti.getName());
        } else if (String.isNotBlank(def.Opportunity_Record_Type__c)) {
            ins.notSuggested.add('Record Type');
        }

        if (!values.containsKey('Name')) {
            String name = SigTokens.fill(def.Opportunity_Name_Pattern__c, ins.tokens);
            if (String.isNotBlank(name)) {
                values.put('Name', name.left(120));
            } else {
                ins.notSuggested.add('Opportunity Name');
            }
        }
        if (values.get('Name') != null) {
            ins.tokens.put('OpportunityName', String.valueOf(values.get('Name')));
        }

        if (!values.containsKey('StageName')) {
            String stage = openStage(def.Opportunity_Stage__c);
            if (stage != null) {
                values.put('StageName', stage);
            } else {
                ins.notSuggested.add('Stage');
            }
        }

        if (!values.containsKey('CloseDate')) {
            if (def.Close_Date_Offset_Days__c != null) {
                values.put('CloseDate', SigClock.today().addDays(def.Close_Date_Offset_Days__c.intValue()));
            } else {
                ins.notSuggested.add('Close Date');
            }
        }
    }

    public static Schema.RecordTypeInfo recordTypeInfo(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        Schema.RecordTypeInfo rti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(developerName.trim());
        return (rti != null && rti.isActive() && rti.isAvailable()) ? rti : null;
    }

    /** The stage, only if it exists, is active and is open. A closed stage is never suggested. */
    public static String openStage(String stage) {
        if (String.isBlank(stage)) {
            return null;
        }
        String wanted = stage.trim();
        for (OpportunityStage s : [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE MasterLabel = :wanted AND IsActive = TRUE AND IsClosed = FALSE
            LIMIT 1
        ]) {
            return s.MasterLabel;
        }
        return null;
    }
}

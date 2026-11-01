/**
 * Duplicate-pipeline check.
 *
 * Runs without sharing on purpose, and answers only yes or no: an open Opportunity the
 * advisor cannot see must still stop a duplicate from being suggested. It never returns
 * the record or any of its fields. This is the framework's only read outside user mode.
 */
public without sharing class SigGuards {
    public static Boolean hasOpenOpportunity(Id accountId, String recordTypeDevName) {
        if (accountId == null) {
            return false;
        }
        String soql = 'SELECT COUNT() FROM Opportunity WHERE AccountId = :accountId AND IsClosed = false';
        Map<String, Object> binds = new Map<String, Object>{ 'accountId' => accountId };
        if (String.isNotBlank(recordTypeDevName) && Schema.SObjectType.Opportunity.fields.getMap().containsKey('recordtypeid')) {
            soql += ' AND RecordType.DeveloperName = :recordTypeDevName';
            binds.put('recordTypeDevName', recordTypeDevName);
        }
        return Database.countQueryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE) > 0;
    }
}

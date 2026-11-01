/**
 * The client behind an anchor record: its Id, name, record type and (for person
 * accounts) contact. Queries are dynamic so the framework deploys to orgs with or
 * without record types and person accounts.
 */
public with sharing class SigRecordInfo {
    public Id recordId;
    public Id clientId;
    public String clientName;
    public String clientRecordType;
    public Id personContactId;

    public static SigRecordInfo load(Id recordId) {
        if (recordId == null) {
            return null;
        }
        Map<String, Schema.SObjectField> accountFields = Schema.SObjectType.Account.fields.getMap();
        Boolean hasRecordType = accountFields.containsKey('recordtypeid');
        Boolean isPersonEnabled = accountFields.containsKey('personcontactid');
        Map<String, Object> binds = new Map<String, Object>{ 'recordId' => recordId };

        SigRecordInfo info = new SigRecordInfo();
        info.recordId = recordId;
        SObjectType anchorType = recordId.getSObjectType();

        if (anchorType == Account.SObjectType) {
            String soql =
                'SELECT Id, Name' +
                (hasRecordType ? ', RecordType.DeveloperName' : '') +
                (isPersonEnabled ? ', PersonContactId' : '') +
                ' FROM Account WHERE Id = :recordId';
            List<SObject> rows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
            if (rows.isEmpty()) {
                return null;
            }
            readAccount(info, rows[0], hasRecordType, isPersonEnabled);
        } else if (anchorType == Opportunity.SObjectType) {
            String soql =
                'SELECT Id, AccountId, Account.Name' +
                (hasRecordType ? ', Account.RecordType.DeveloperName' : '') +
                (isPersonEnabled ? ', Account.PersonContactId' : '') +
                ' FROM Opportunity WHERE Id = :recordId';
            List<SObject> rows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
            if (rows.isEmpty()) {
                return null;
            }
            SObject account = rows[0].getSObject('Account');
            if (account != null) {
                readAccount(info, account, hasRecordType, isPersonEnabled);
            }
        } else {
            throw new SigException('Unsupported anchor object: ' + anchorType);
        }
        return info;
    }

    private static void readAccount(SigRecordInfo info, SObject account, Boolean hasRecordType, Boolean isPersonEnabled) {
        info.clientId = (Id) account.get('Id');
        info.clientName = (String) account.get('Name');
        if (hasRecordType && account.getSObject('RecordType') != null) {
            info.clientRecordType = (String) account.getSObject('RecordType').get('DeveloperName');
        }
        if (isPersonEnabled) {
            info.personContactId = (Id) account.get('PersonContactId');
        }
    }
}

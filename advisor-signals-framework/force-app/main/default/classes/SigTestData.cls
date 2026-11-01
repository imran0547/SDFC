/**
 * Test helpers: in-memory metadata rows, a test advisor and records.
 * Custom metadata rows cannot be inserted in tests, so they are built from JSON and
 * handed to SigConfig through its @TestVisible overrides.
 */
@IsTest
public class SigTestData {
    public static Signal_Definition__mdt definition(Map<String, Object> fields) {
        Map<String, Object> f = new Map<String, Object>{
            'DeveloperName' => 'Test_' + String.valueOf(fields.get('Signal_Key__c')),
            'MasterLabel' => 'Test',
            'Is_Active__c' => true,
            'Agent__c' => 'Insight',
            'Anchor_Object__c' => 'Account',
            'Show_On_Ask__c' => true,
            'Resurface_Days__c' => 0,
            'Allow_Task__c' => true,
            'Secondary_Action_Label__c' => 'Not now',
            'Task_Due_Business_Days__c' => 2
        };
        f.putAll(fields);
        return (Signal_Definition__mdt) JSON.deserialize(JSON.serialize(f), Signal_Definition__mdt.class);
    }

    public static Signal_Parameter__mdt parameter(String signalKey, String ruleKey, String name, String value) {
        return parameter(signalKey, ruleKey, name, value, new Map<String, Object>());
    }

    public static Signal_Parameter__mdt parameter(
        String signalKey,
        String ruleKey,
        String name,
        String value,
        Map<String, Object> scope
    ) {
        Map<String, Object> f = new Map<String, Object>{
            'DeveloperName' => (signalKey + '_' + ruleKey + '_' + name).replaceAll('[^A-Za-z0-9_]', '_').left(40),
            'MasterLabel' => name,
            'Signal_Key__c' => signalKey,
            'Is_Active__c' => true,
            'Rule_Key__c' => ruleKey,
            'Parameter_Name__c' => name,
            'Parameter_Value__c' => value
        };
        f.putAll(scope);
        return (Signal_Parameter__mdt) JSON.deserialize(JSON.serialize(f), Signal_Parameter__mdt.class);
    }

    public static Signal_Audience__mdt audience(String signalKey, String groupName) {
        Map<String, Object> f = new Map<String, Object>{
            'DeveloperName' => 'Aud_' + signalKey,
            'MasterLabel' => 'Audience',
            'Signal_Key__c' => signalKey,
            'Permission_Set_Group__c' => groupName,
            'Is_Active__c' => true
        };
        return (Signal_Audience__mdt) JSON.deserialize(JSON.serialize(f), Signal_Audience__mdt.class);
    }

    public static void configure(
        List<Signal_Definition__mdt> definitions,
        List<Signal_Parameter__mdt> parameters,
        List<Signal_Audience__mdt> audiences
    ) {
        SigConfig.definitionsOverride = definitions;
        SigConfig.parametersOverride = parameters == null ? new List<Signal_Parameter__mdt>() : parameters;
        SigConfig.audiencesOverride = audiences == null ? new List<Signal_Audience__mdt>() : audiences;
        SigAccess.groupsOverride = new Set<String>();
        SigAccess.customPermissionsOverride = new Set<String>();
        SigDates.useBusinessHours = false;
    }

    /** A user with a standard profile and the framework permission set. */
    public static User advisor() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        if (profiles.isEmpty()) {
            profiles = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        }
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            ProfileId = profiles[0].Id,
            LastName = 'Advisor',
            FirstName = 'Test',
            Alias = 'sigadv',
            Email = 'sig.advisor@example.com',
            Username = 'sig.advisor.' + unique + '@example.com',
            TimeZoneSidKey = 'America/Chicago',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Signal_Framework_User' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        return u;
    }

    /** First open, active Opportunity stage in the org. */
    public static String openStage() {
        return [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = FALSE ORDER BY SortOrder LIMIT 1].MasterLabel;
    }

    public static Account client(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    public static Opportunity opportunity(Id accountId, String name) {
        Opportunity o = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = openStage(),
            CloseDate = Date.today().addDays(30)
        );
        insert o;
        return o;
    }
}

@IsTest
private class SigConfigTest {
    private static final String KEY = 'RULES_TEST';

    @IsTest
    static void smallestMatchingThresholdWinsAndItsParametersTravelWithIt() {
        Signal_Definition__mdt def = SigTestData.definition(new Map<String, Object>{ 'Signal_Key__c' => KEY, 'Rule_Sort_Parameter__c' => 'Threshold_Days' });
        Map<String, Object> proposalScope = new Map<String, Object>{ 'Scope_Stage__c' => 'Proposal' };
        SigTestData.configure(
            new List<Signal_Definition__mdt>{ def },
            new List<Signal_Parameter__mdt>{
                SigTestData.parameter(KEY, 'DEFAULT', 'Threshold_Days', '30'),
                SigTestData.parameter(KEY, 'DEFAULT', 'Next_Stage', 'Review'),
                SigTestData.parameter(KEY, 'PROPOSAL', 'Threshold_Days', '14', proposalScope),
                SigTestData.parameter(KEY, 'PROPOSAL', 'Next_Stage', 'Commitment', proposalScope),
                SigTestData.parameter(KEY, null, 'Comparison', 'GreaterOrEqual'),
                SigTestData.parameter(KEY, 'GROUPED', 'Threshold_Days', '1', new Map<String, Object>{ 'Permission_Set_Group__c' => 'Other_Group' })
            },
            null
        );

        SigConfig.Rule proposal = SigConfig.resolveRule(def, new Set<String>(), null, 'Proposal', null);
        Assert.areEqual(14, proposal.getInteger('Threshold_Days'));
        Assert.areEqual('Commitment', proposal.getText('Next_Stage'));
        Assert.areEqual('GreaterOrEqual', proposal.getText('Comparison'), 'Global parameters apply to every rule.');

        SigConfig.Rule other = SigConfig.resolveRule(def, new Set<String>(), null, 'Discovery', null);
        Assert.areEqual(30, other.getInteger('Threshold_Days'));
        Assert.areEqual('Review', other.getText('Next_Stage'));

        SigConfig.Rule grouped = SigConfig.resolveRule(def, new Set<String>{ 'Other_Group' }, null, 'Discovery', null);
        Assert.areEqual(1, grouped.getInteger('Threshold_Days'), 'A group-scoped rule applies only to that group.');
    }

    @IsTest
    static void typedGettersAndLists() {
        Signal_Definition__mdt def = SigTestData.definition(new Map<String, Object>{ 'Signal_Key__c' => KEY });
        SigTestData.configure(
            new List<Signal_Definition__mdt>{ def },
            new List<Signal_Parameter__mdt>{
                SigTestData.parameter(KEY, null, 'Rate', '4.5%'),
                SigTestData.parameter(KEY, null, 'Flag', 'true'),
                SigTestData.parameter(KEY, null, 'Words', 'one | two\nthree'),
                SigTestData.parameter(KEY, null, 'Bad', 'abc')
            },
            null
        );
        SigConfig.Rule r = SigConfig.resolveRule(def, null, null, null, null);
        Assert.areEqual(4.5, r.getDecimal('Rate'));
        Assert.areEqual(4, r.getInteger('Rate'));
        Assert.isTrue(r.getBoolean('Flag'));
        Assert.isFalse(r.getBoolean('Missing'));
        Assert.areEqual(new List<String>{ 'one', 'two', 'three' }, r.getList('Words'));
        Assert.isNull(r.getDecimal('Bad'));
        Assert.isFalse(r.has('Missing'));
    }

    @IsTest
    static void definitionsAudiencesAndRecordTypes() {
        Signal_Definition__mdt active = SigTestData.definition(new Map<String, Object>{
            'Signal_Key__c' => 'A',
            'Included_Record_Types__c' => 'Individual,\nBusiness'
        });
        Signal_Definition__mdt inactive = SigTestData.definition(new Map<String, Object>{ 'Signal_Key__c' => 'B', 'Is_Active__c' => false });
        SigTestData.configure(new List<Signal_Definition__mdt>{ active, inactive }, null, new List<Signal_Audience__mdt>{ SigTestData.audience('A', 'Advisors') });

        Assert.areEqual(1, SigConfig.activeDefinitions('Account', null).size());
        Assert.areEqual(0, SigConfig.activeDefinitions('Opportunity', null).size());
        Assert.areEqual(0, SigConfig.activeDefinitions('Account', 'Next Best Action').size());
        Assert.areEqual('B', SigConfig.definition('b').Signal_Key__c);
        Assert.isTrue(SigConfig.recordTypeIncluded(active, 'business'));
        Assert.isFalse(SigConfig.recordTypeIncluded(active, 'Trust'));
        Assert.isFalse(SigConfig.recordTypeIncluded(active, null));
        Assert.isTrue(SigConfig.recordTypeIncluded(inactive, null), 'Blank list includes every client type.');
        Assert.isFalse(SigConfig.audienceAllows('A', new Set<String>()));
        Assert.isTrue(SigConfig.audienceAllows('A', new Set<String>{ 'Advisors' }));
        Assert.isTrue(SigConfig.audienceAllows('B', new Set<String>()), 'No audience rows means open to all.');

        try {
            SigConfig.sourceFor(SigTestData.definition(new Map<String, Object>{ 'Signal_Key__c' => 'C', 'Source_Class__c' => 'SigTokens' }));
            Assert.fail('A class that is not a SigSource must be refused.');
        } catch (SigException e) {
            Assert.isTrue(e.getMessage().contains('does not implement'));
        }
    }

    @IsTest
    static void liveMetadataQueriesRun() {
        // Reads the deployed sample rows without overrides; only checks that the queries run.
        Assert.isNotNull(SigConfig.definitions());
        Assert.isNotNull(SigConfig.audiences());
        Assert.isNotNull(SigConfig.parameters());
    }
}

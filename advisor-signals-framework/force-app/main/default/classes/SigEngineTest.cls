@IsTest
private class SigEngineTest {
    private static final String KEY = 'STALLED_TEST';

    private static Signal_Definition__mdt stalledDefinition(Map<String, Object> overrides) {
        Map<String, Object> f = new Map<String, Object>{
            'Signal_Key__c' => KEY,
            'Agent__c' => 'Next Best Action',
            'Anchor_Object__c' => 'Opportunity',
            'Source_Class__c' => 'SigStalledOpportunitySource',
            'Prompt_Template__c' => '{OpportunityName} has stayed in {Stage} for {Days} days (threshold {Threshold}).',
            'Primary_Action__c' => 'Update Opportunity',
            'Primary_Action_Label__c' => 'Update Opportunity',
            'Rule_Sort_Parameter__c' => 'Threshold_Days'
        };
        f.putAll(overrides);
        return SigTestData.definition(f);
    }

    private static List<Signal_Parameter__mdt> stalledParameters(Integer threshold) {
        return new List<Signal_Parameter__mdt>{
            SigTestData.parameter(KEY, 'ANY', 'Threshold_Days', String.valueOf(threshold)),
            SigTestData.parameter(KEY, 'ANY', 'Close_Date_Offset_Days', '10'),
            SigTestData.parameter(KEY, 'ANY', 'Default_Next_Step', 'Call the client to agree next steps'),
            SigTestData.parameter(KEY, null, 'Comparison', 'GreaterOrEqual')
        };
    }

    @IsTest
    static void stalledOpportunityIsShownAndNotNowHidesItForTheSession() {
        SigTestData.configure(new List<Signal_Definition__mdt>{ stalledDefinition(new Map<String, Object>()) }, stalledParameters(0), null);
        User u = SigTestData.advisor();
        System.runAs(u) {
            Account a = SigTestData.client('Hargrove Test');
            Opportunity o = SigTestData.opportunity(a.Id, 'Retirement Plan Review');
            Test.startTest();
            List<SigInsight> found = SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, 'session-1');
            Assert.areEqual(1, found.size(), 'A 0-day threshold is met on day 0.');
            SigInsight ins = found[0];
            Assert.isTrue(ins.prompt.startsWith('Retirement Plan Review has stayed in'), ins.prompt);
            Assert.isTrue(ins.responseKey.endsWith('|' + u.Id), 'Response key ends with the user Id.');
            Assert.areEqual(Date.today().addDays(10), ins.suggestedValues.get('CloseDate'));
            Assert.areEqual('Update Opportunity', ins.primaryLabel);
            Assert.areEqual(String.valueOf(a.Id), ins.clientId);

            SigResponseService.record(ins, SigResponseService.NOT_NOW, SigEngine.SURFACE_RECORD_PAGE, 'session-1', null);
            Assert.areEqual(0, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, 'session-1').size(), 'Hidden in the same session.');
            List<SigInsight> asked = SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_AGENT, true, null);
            Assert.areEqual(1, asked.size(), 'Shown when the advisor asks.');
            Assert.isNotNull(asked[0].reminderText, 'Shown with a skipped-on reminder.');
            Assert.areEqual(1, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, 'session-2').size(), 'Back in a new session.');

            SigResponseService.record(ins, SigResponseService.ACTED_ON, SigEngine.SURFACE_RECORD_PAGE, 'session-2', o.Id);
            Assert.areEqual(0, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_AGENT, true, null).size(), 'Never shown after Acted On.');
            Test.stopTest();
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Signal_Response__c], 'One row per advisor and signal instance.');
    }

    @IsTest
    static void thresholdNotMetShowsNothing() {
        SigTestData.configure(new List<Signal_Definition__mdt>{ stalledDefinition(new Map<String, Object>()) }, stalledParameters(5), null);
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'New Opportunity');
            Assert.areEqual(0, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size());
        }
    }

    @IsTest
    static void resurfaceDaysHideEvenOnAskUntilTheWaitHasPassed() {
        Signal_Definition__mdt def = stalledDefinition(new Map<String, Object>{ 'Resurface_Days__c' => 5, 'Show_On_Ask__c' => false });
        SigTestData.configure(new List<Signal_Definition__mdt>{ def }, stalledParameters(0), null);
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Opp');
            SigInsight ins = SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null)[0];
            SigResponseService.record(ins, SigResponseService.NOT_NOW, SigEngine.SURFACE_RECORD_PAGE, null, null);
            Assert.areEqual(0, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_AGENT, true, null).size(), 'Hidden during the wait, even when asked.');
            SigClock.nowOverride = Datetime.now().addDays(6);
            List<SigInsight> later = SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null);
            Assert.areEqual(1, later.size(), 'Back after the wait.');
            Assert.isNotNull(later[0].reminderText);
        }
    }

    @IsTest
    static void audienceAndRecordTypeLimitWhoSeesASignal() {
        Signal_Definition__mdt def = stalledDefinition(new Map<String, Object>());
        SigTestData.configure(
            new List<Signal_Definition__mdt>{ def },
            stalledParameters(0),
            new List<Signal_Audience__mdt>{ SigTestData.audience(KEY, 'Advisor_Access_Group') }
        );
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Opp');
            Assert.areEqual(0, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size(), 'Not in the audience group.');
            SigAccess.groupsOverride = new Set<String>{ 'Advisor_Access_Group' };
            Assert.areEqual(1, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size(), 'In the audience group.');

            SigConfig.definitionsOverride = new List<Signal_Definition__mdt>{
                stalledDefinition(new Map<String, Object>{ 'Included_Record_Types__c' => 'Some_Other_Client_Type' })
            };
            Assert.areEqual(0, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size(), 'Client type not included.');
            Assert.areEqual(0, SigEngine.evaluate(o.Id, 'Insight', SigEngine.SURFACE_RECORD_PAGE, false, null).size(), 'Other agent filtered out.');
        }
    }

    @IsTest
    static void aFailingSourceIsLoggedAndOtherSignalsStillRun() {
        Signal_Definition__mdt broken = SigTestData.definition(new Map<String, Object>{
            'Signal_Key__c' => 'BROKEN',
            'Anchor_Object__c' => 'Opportunity',
            'Source_Class__c' => 'NoSuchSignalSource',
            'Primary_Action__c' => 'Update Opportunity'
        });
        SigTestData.configure(new List<Signal_Definition__mdt>{ broken, stalledDefinition(new Map<String, Object>()) }, stalledParameters(0), null);
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Opp');
            Assert.areEqual(1, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size());
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Signal_Log__c WHERE Signal_Key__c = 'BROKEN' AND Level__c = 'Error']);
    }

    @IsTest
    static void recheckAndResponseOwnership() {
        SigTestData.configure(new List<Signal_Definition__mdt>{ stalledDefinition(new Map<String, Object>()) }, stalledParameters(0), null);
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Opp');
            SigInsight ins = SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null)[0];
            Assert.isTrue(SigEngine.recheck(o.Id, ins.responseKey));
            Assert.isFalse(SigEngine.recheck(o.Id, 'not-a-key'));

            ins.responseKey = ins.responseKey.substringBeforeLast('|') + '|005000000000000AAA';
            try {
                SigResponseService.record(ins, SigResponseService.NOT_NOW, SigEngine.SURFACE_RECORD_PAGE, null, null);
                Assert.fail('Another user\'s response key must be refused.');
            } catch (SigException e) {
                Assert.isTrue(e.getMessage().contains('advisor it belongs to'));
            }
        }
    }

    @IsTest
    static void closedOpportunityIsNeverStalled() {
        SigTestData.configure(new List<Signal_Definition__mdt>{ stalledDefinition(new Map<String, Object>()) }, stalledParameters(0), null);
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Opp');
            o.StageName = [SELECT MasterLabel FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = TRUE LIMIT 1].MasterLabel;
            update o;
            Assert.areEqual(0, SigEngine.evaluate(o.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size());
        }
    }

    @IsTest
    static void pickBestKeepsHighestRankThenNewest() {
        SigInsight older = new SigInsight();
        older.changeType = 'X';
        older.evidenceDate = Date.today().addDays(-5);
        SigInsight newer = new SigInsight();
        newer.changeType = 'X';
        newer.evidenceDate = Date.today();
        SigInsight ranked = new SigInsight();
        ranked.changeType = 'X';
        ranked.rank = 2;
        ranked.evidenceDate = Date.today().addDays(-10);
        Assert.areEqual(newer, SigEngine.pickBest(new List<SigInsight>{ older, newer })[0]);
        Assert.areEqual(ranked, SigEngine.pickBest(new List<SigInsight>{ older, newer, ranked })[0]);
    }
}

@IsTest
private class SigAgentActionsTest {
    private static final String KEY = 'AGENT_TEST';

    private static void setUp() {
        SigTestData.configure(
            new List<Signal_Definition__mdt>{
                SigTestData.definition(new Map<String, Object>{
                    'Signal_Key__c' => KEY,
                    'Agent__c' => 'Next Best Action',
                    'Anchor_Object__c' => 'Opportunity',
                    'Source_Class__c' => 'SigStalledOpportunitySource',
                    'Prompt_Template__c' => '{OpportunityName} is stalled.',
                    'Primary_Action__c' => 'Update Opportunity',
                    'Primary_Action_Label__c' => 'Update Opportunity',
                    'Allow_Task__c' => true
                })
            },
            new List<Signal_Parameter__mdt>{ SigTestData.parameter(KEY, 'ANY', 'Threshold_Days', '0') },
            null
        );
    }

    @IsTest
    static void identifyRecordByName() {
        System.runAs(SigTestData.advisor()) {
            Account one = SigTestData.client('Hargrove Family');
            SigTestData.client('Hargrove Trust');
            SigTestData.client('Nair');

            SigFindRecordAction.Request req = new SigFindRecordAction.Request();
            req.name = 'Nair';
            SigFindRecordAction.Response res = SigFindRecordAction.run(new List<SigFindRecordAction.Request>{ req })[0];
            Assert.areEqual(1, res.matchCount);
            Assert.isNotNull(res.recordId);

            req.name = 'Hargrove';
            res = SigFindRecordAction.run(new List<SigFindRecordAction.Request>{ req })[0];
            Assert.areEqual(2, res.matchCount);
            Assert.isNull(res.recordId);
            Assert.isTrue(res.matchesText.contains('Hargrove Family'));

            req.name = 'Hargrove Family';
            Assert.areEqual(String.valueOf(one.Id), SigFindRecordAction.run(new List<SigFindRecordAction.Request>{ req })[0].recordId);

            req.name = 'Nobody';
            Assert.areEqual(0, SigFindRecordAction.run(new List<SigFindRecordAction.Request>{ req })[0].matchCount);
            req.name = 'x';
            Assert.isTrue(SigFindRecordAction.run(new List<SigFindRecordAction.Request>{ req })[0].message.contains('two letters'));
        }
    }

    @IsTest
    static void getSignalsPastResponsesAndFollowUps() {
        setUp();
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Plan Review');

            SigGetSignalsAction.Request getReq = new SigGetSignalsAction.Request();
            getReq.recordId = o.Id;
            getReq.agent = 'Next Best Action';
            SigGetSignalsAction.Response got = SigGetSignalsAction.run(new List<SigGetSignalsAction.Request>{ getReq })[0];
            Assert.areEqual(1, got.count);
            Assert.isTrue(got.signalsText.contains('Sentence: Plan Review is stalled.'));
            String responseKey = got.responseKeys[0];

            SigGetFollowUpsAction.Request fuReq = new SigGetFollowUpsAction.Request();
            fuReq.recordId = o.Id;
            fuReq.responseKey = responseKey;
            Assert.areEqual(new List<String>{ 'Task' }, SigGetFollowUpsAction.run(new List<SigGetFollowUpsAction.Request>{ fuReq })[0].options);

            // After the advisor acts, follow-ups still work from the stored response.
            SigInsight live = SigEngine.findInsight(o.Id, responseKey);
            SigResponseService.record(live, SigResponseService.ACTED_ON, SigEngine.SURFACE_AGENT, null, o.Id);

            SigCreateFollowUpAction.Request createReq = new SigCreateFollowUpAction.Request();
            createReq.recordId = o.Id;
            createReq.responseKey = responseKey;
            SigCreateFollowUpAction.Response draft = SigCreateFollowUpAction.run(new List<SigCreateFollowUpAction.Request>{ createReq })[0];
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(draft.draftJson);
            Assert.areEqual('Task', parsed.get('objectApiName'));
            Assert.isTrue(draft.summary.startsWith('Task "Plan Review"'), draft.summary);
            Assert.areEqual(0, [SELECT COUNT() FROM Task], 'The action never saves the Task.');

            createReq.followUpType = 'Meeting';
            Assert.isNull(SigCreateFollowUpAction.run(new List<SigCreateFollowUpAction.Request>{ createReq })[0].draftJson);

            fuReq.responseKey = 'unknown';
            Assert.isTrue(SigGetFollowUpsAction.run(new List<SigGetFollowUpsAction.Request>{ fuReq })[0].options.isEmpty());

            SigPastResponsesAction.Request pastReq = new SigPastResponsesAction.Request();
            pastReq.recordId = o.Id;
            SigPastResponsesAction.Response past = SigPastResponsesAction.run(new List<SigPastResponsesAction.Request>{ pastReq })[0];
            Assert.areEqual(1, past.count);
            Assert.isTrue(past.responsesText.contains('Acted On'));

            getReq.recordId = 'bad';
            Assert.areEqual(0, SigGetSignalsAction.run(new List<SigGetSignalsAction.Request>{ getReq })[0].count);
            pastReq.recordId = 'bad';
            Assert.areEqual(0, SigPastResponsesAction.run(new List<SigPastResponsesAction.Request>{ pastReq })[0].count);
        }
    }
}

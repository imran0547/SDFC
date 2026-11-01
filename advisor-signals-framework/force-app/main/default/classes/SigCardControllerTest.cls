@IsTest
private class SigCardControllerTest {
    private static final String KEY = 'CTRL_TEST';

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
                    'Task_Priority__c' => 'Normal',
                    'Task_Due_Business_Days__c' => 2
                })
            },
            new List<Signal_Parameter__mdt>{
                SigTestData.parameter(KEY, 'ANY', 'Threshold_Days', '0'),
                SigTestData.parameter(KEY, 'ANY', 'Default_Next_Step', 'Agree next steps')
            },
            null
        );
    }

    @IsTest
    static void cardLifecycle() {
        setUp();
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Plan Review');
            List<SigInsight> found = SigCardController.getInsights(o.Id, null, 'Record Page', false, 'tok');
            Assert.areEqual(1, found.size());
            String insightJson = JSON.serialize(found[0]);

            Assert.isTrue(SigCardController.recheck(o.Id, found[0].responseKey));

            Map<String, Object> task = SigCardController.getTaskDefaults(insightJson, o.Id);
            Assert.areEqual(o.Id, task.get('WhatId'));
            Assert.areEqual('Normal', task.get('Priority'));
            Assert.isNotNull(task.get('ActivityDate'));
            Assert.isTrue(String.valueOf(task.get('Description')).contains('Next step: Agree next steps'));

            SigCardController.recordResponse(insightJson, 'Not Now', 'Record Page', 'tok', null);
            Assert.areEqual(0, SigCardController.getInsights(o.Id, null, 'Record Page', false, 'tok').size());

            try {
                SigCardController.recordResponse(insightJson, 'Maybe', 'Record Page', 'tok', null);
                Assert.fail('Unknown status must be refused.');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Nothing else was changed'));
            }
            SigCardController.logClientError(KEY, o.Id, 'Test message');
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Signal_Log__c WHERE Signal_Key__c = :KEY AND Level__c = 'Warning']);
    }

    @IsTest
    static void agentActionsReturnCardsAndRecordNotNow() {
        setUp();
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Opportunity o = SigTestData.opportunity(a.Id, 'Plan Review');

            SigAgentAction.Request req = new SigAgentAction.Request();
            req.recordId = o.Id;
            SigAgentAction.Response res = SigAgentAction.run(new List<SigAgentAction.Request>{ req })[0];
            Assert.areEqual(1, res.count);
            Assert.isTrue(res.summary.contains('Plan Review is stalled.'));
            List<Object> cards = (List<Object>) JSON.deserializeUntyped(res.cardsJson);
            String responseKey = (String) ((Map<String, Object>) cards[0]).get('responseKey');

            SigRecordResponseAction.Request notNow = new SigRecordResponseAction.Request();
            notNow.recordId = o.Id;
            notNow.responseKey = responseKey;
            SigRecordResponseAction.Response saved = SigRecordResponseAction.run(new List<SigRecordResponseAction.Request>{ notNow })[0];
            Assert.isTrue(saved.saved);

            notNow.responseKey = 'unknown';
            Assert.isFalse(SigRecordResponseAction.run(new List<SigRecordResponseAction.Request>{ notNow })[0].saved);

            req.recordId = 'not-an-id';
            SigAgentAction.Response failed = SigAgentAction.run(new List<SigAgentAction.Request>{ req })[0];
            Assert.areEqual(0, failed.count);
            Assert.areEqual('[]', failed.cardsJson);
        }
        Assert.areEqual('There are no signals for this record right now.', SigAgentAction.summarize(new List<SigInsight>()));
    }
}

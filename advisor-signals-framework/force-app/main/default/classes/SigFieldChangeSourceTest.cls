@IsTest
private class SigFieldChangeSourceTest {
    private static final String KEY = 'EMPLOYER_TEST';

    private class StubHistory implements SigFieldChangeSource.HistoryProvider {
        List<SigFieldChangeSource.Change> rows;
        StubHistory(List<SigFieldChangeSource.Change> rows) {
            this.rows = rows;
        }
        public List<SigFieldChangeSource.Change> changes(Id accountId, String fieldName, Datetime since) {
            return rows;
        }
    }

    private static void setUp(String excludePattern) {
        List<Signal_Parameter__mdt> params = new List<Signal_Parameter__mdt>{
            SigTestData.parameter(KEY, null, 'Tracked_Field', 'Employer__c'),
            SigTestData.parameter(KEY, null, 'Change_Type', 'Job Change')
        };
        if (excludePattern != null) {
            params.add(SigTestData.parameter(KEY, null, 'Exclude_Pattern', excludePattern));
        }
        SigTestData.configure(
            new List<Signal_Definition__mdt>{
                SigTestData.definition(new Map<String, Object>{
                    'Signal_Key__c' => KEY,
                    'Source_Class__c' => 'SigFieldChangeSource',
                    'Primary_Action__c' => 'Draft Opportunity',
                    'Primary_Action_Label__c' => 'Draft Opportunity',
                    'Prompt_Template__c' => '{ClientName}: {Change} on {Date} ({Source}). Draft {OpportunityName}?',
                    'Opportunity_Stage__c' => SigTestData.openStage(),
                    'Opportunity_Name_Pattern__c' => '{ChangeType} - {MMM YYYY}',
                    'Close_Date_Offset_Days__c' => 30,
                    'Lookback_Days__c' => 60
                })
            },
            params,
            null
        );
    }

    private static SigFieldChangeSource.Change change(Object oldValue, Object newValue) {
        return new SigFieldChangeSource.Change('017000000000001AAA', oldValue, newValue, Datetime.now().addDays(-3));
    }

    @IsTest
    static void employerChangeRaisesAnInsightWithDraftValues() {
        setUp(null);
        SigFieldChangeSource.provider = new StubHistory(new List<SigFieldChangeSource.Change>{ change('Acme Corp', 'Globex Inc') });
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Hargrove Test');
            List<SigInsight> found = SigEngine.evaluate(a.Id, 'Insight', SigEngine.SURFACE_RECORD_PAGE, false, null);
            Assert.areEqual(1, found.size());
            SigInsight ins = found[0];
            Assert.areEqual('Job Change', ins.changeType);
            Assert.areEqual('Confirmed', ins.confidence);
            Assert.isTrue(String.valueOf(ins.suggestedValues.get('Name')).startsWith('Job Change - '));
            Assert.areEqual(SigTestData.openStage(), ins.suggestedValues.get('StageName'));
            Assert.areEqual(Date.today().addDays(30), ins.suggestedValues.get('CloseDate'));
            Assert.areEqual(a.Id, ins.suggestedValues.get('AccountId'));
            Assert.isTrue(String.valueOf(ins.suggestedValues.get('Description')).contains('Profile history'));
            Assert.isTrue(ins.prompt.startsWith('Hargrove Test: Job Change on'), ins.prompt);

            insert new Opportunity(Name = 'Open', AccountId = a.Id, StageName = SigTestData.openStage(), CloseDate = Date.today().addDays(10));
            Assert.areEqual(0, SigEngine.evaluate(a.Id, 'Insight', SigEngine.SURFACE_RECORD_PAGE, false, null).size(), 'An open Opportunity prevents a duplicate.');
        }
    }

    @IsTest
    static void spellingAndSuffixFixesAreIgnored() {
        setUp(null);
        SigFieldChangeSource.provider = new StubHistory(new List<SigFieldChangeSource.Change>{ change('Acme Inc', 'ACME, LLC'), change('Globex', '') });
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Assert.areEqual(0, SigEngine.evaluate(a.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size());
        }
        Assert.areEqual('acme', SigFieldChangeSource.normalize('Acme, Inc.'));
        Assert.areEqual('globex corporation holdings', SigFieldChangeSource.normalize('Globex Corporation Holdings'));
    }

    @IsTest
    static void excludePatternRulesAChangeOut() {
        setUp('retired');
        SigFieldChangeSource.provider = new StubHistory(new List<SigFieldChangeSource.Change>{ change('Acme', 'Retired') });
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Assert.areEqual(0, SigEngine.evaluate(a.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size());
        }
    }

    @IsTest
    static void defaultProviderSkipsAFieldThatDoesNotExist() {
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            List<SigFieldChangeSource.Change> rows = new SigFieldChangeSource.AccountHistoryProvider()
                .changes(a.Id, 'No_Such_Field__c', Datetime.now().addDays(-30));
            Assert.areEqual(0, rows.size());
            Assert.areEqual(0, new SigFieldChangeSource.AccountHistoryProvider().changes(a.Id, 'Name', Datetime.now().addDays(-30)).size());
        }
    }
}

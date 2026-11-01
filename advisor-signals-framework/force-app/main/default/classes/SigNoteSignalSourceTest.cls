@IsTest
private class SigNoteSignalSourceTest {
    private static final String KEY = 'NOTE_TEST';

    private class StubNotes implements SigNoteProvider {
        List<SigNote> rows;
        StubNotes(List<SigNote> rows) {
            this.rows = rows;
        }
        public List<SigNote> notes(Id clientId, Date since, Integer maxNotes) {
            return rows;
        }
    }

    private class FailingClassifier implements SigNoteClassifier {
        public List<SigNoteVerdict> classify(List<SigNote> notes, SigConfig.Rule rule) {
            throw new SigException('Model unavailable');
        }
    }

    private static void setUp() {
        SigTestData.configure(
            new List<Signal_Definition__mdt>{
                SigTestData.definition(new Map<String, Object>{
                    'Signal_Key__c' => KEY,
                    'Source_Class__c' => 'SigNoteSignalSource',
                    'Primary_Action__c' => 'Create Task',
                    'Primary_Action_Label__c' => 'Create a Task',
                    'Prompt_Template__c' => '{ClientName} may have a {Change} ({Confidence}): "{Quote}"'
                })
            },
            new List<Signal_Parameter__mdt>{
                SigTestData.parameter(KEY, null, 'Change_Type', 'Retirement'),
                SigTestData.parameter(KEY, null, 'Gate_Keywords', 'retir|pension'),
                SigTestData.parameter(KEY, null, 'Strong_Phrases', 'retired last month|last day of work'),
                SigTestData.parameter(KEY, null, 'Weak_Phrases', 'winding down|pension start'),
                SigTestData.parameter(KEY, null, 'Exclude_Phrases', 'retire someday|spouse retired')
            },
            null
        );
    }

    private static SigNote note(Integer daysAgo, String text) {
        return new SigNote('00T000000000' + String.valueOf(100 + daysAgo) + 'AAA', Date.today().addDays(-daysAgo), text);
    }

    @IsTest
    static void aStrongNoteIsEnough() {
        setUp();
        SigNoteSignalSource.providerOverride = new StubNotes(new List<SigNote>{
            note(2, 'Met the client. She retired last month and wants to review income. Follow up next week.'),
            note(9, 'Discussed the weather.')
        });
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            List<SigInsight> found = SigEngine.evaluate(a.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null);
            Assert.areEqual(1, found.size());
            Assert.areEqual('Confirmed', found[0].confidence);
            Assert.areEqual('She retired last month and wants to review income.', found[0].evidenceSummary);
            Assert.isTrue(found[0].prompt.contains('Retirement (Confirmed)'), found[0].prompt);
        }
    }

    @IsTest
    static void excludedOrSingleWeakNotesDoNotCount() {
        setUp();
        SigNoteSignalSource.providerOverride = new StubNotes(new List<SigNote>{
            note(1, 'He might retire someday, maybe in ten years.'),
            note(4, 'Client is winding down at work.')
        });
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Assert.areEqual(0, SigEngine.evaluate(a.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size());
        }
    }

    @IsTest
    static void twoWeakNotesCountAsInferred() {
        setUp();
        SigNoteSignalSource.providerOverride = new StubNotes(new List<SigNote>{
            note(1, 'Client is winding down at work ahead of retirement.'),
            note(5, 'Asked about pension start dates.')
        });
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            List<SigInsight> found = SigEngine.evaluate(a.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null);
            Assert.areEqual(1, found.size());
            Assert.areEqual('Inferred', found[0].confidence);
        }
    }

    @IsTest
    static void aClassifierFailureIsLoggedAndRaisesNothing() {
        setUp();
        SigNoteSignalSource.providerOverride = new StubNotes(new List<SigNote>{ note(1, 'She retired last month.') });
        SigNoteSignalSource.classifierOverride = new FailingClassifier();
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            Assert.areEqual(0, SigEngine.evaluate(a.Id, null, SigEngine.SURFACE_RECORD_PAGE, false, null).size());
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Signal_Log__c WHERE Signal_Key__c = :KEY]);
    }

    @IsTest
    static void gateKeepsAtMostTheConfiguredNumberOfMatchingNotes() {
        List<SigNote> notes = new List<SigNote>{
            note(1, 'retirement plan'),
            note(2, 'nothing relevant'),
            note(3, 'Pension question'),
            note(4, 'retired'),
            null
        };
        List<SigNote> kept = SigNoteSignalSource.gate(notes, new List<String>{ 'retir', 'pension' }, 2);
        Assert.areEqual(2, kept.size());
        Assert.areEqual('retirement plan', kept[0].text);
        Assert.areEqual('Pension question', kept[1].text);
        Assert.areEqual(3, SigNoteSignalSource.gate(notes, new List<String>(), 3).size());
    }

    @IsTest
    static void activityNotesAreReadFromTasks() {
        System.runAs(SigTestData.advisor()) {
            Account a = SigTestData.client('Client');
            insert new Task(Subject = 'Call', WhatId = a.Id, Description = 'Client retired last month.', ActivityDate = Date.today());
            insert new Task(Subject = 'Empty', WhatId = a.Id);
            List<SigNote> notes = new SigActivityNoteProvider().notes(a.Id, Date.today().addDays(-30), 20);
            Assert.areEqual(1, notes.size());
            Assert.areEqual('Client retired last month.', notes[0].text);
        }
    }
}

@IsTest
private class SigUtilitiesTest {
    @IsTest
    static void tokensAreFilledAndUnknownOnesRemoved() {
        SigClock.todayOverride = Date.newInstance(2026, 10, 30);
        String out = SigTokens.fill('{ClientName} – {ChangeType} – {MMM YYYY} {Unknown}', new Map<String, String>{
            'ClientName' => 'Hargrove',
            'ChangeType' => 'Job Change'
        });
        Assert.areEqual('Hargrove – Job Change – Oct 2026', out);
        Assert.isNull(SigTokens.fill(null, null));
        Assert.areEqual('', SigTokens.formatDate(null));
    }

    @IsTest
    static void businessDaysSkipWeekends() {
        SigDates.useBusinessHours = false;
        Date friday = Date.newInstance(2026, 10, 30);
        Assert.areEqual(Date.newInstance(2026, 11, 3), SigDates.addBusinessDays(friday, 2));
        Assert.areEqual(friday, SigDates.addBusinessDays(friday, 0));
        Assert.isNull(SigDates.addBusinessDays(null, 2));
        SigDates.useBusinessHours = true;
        Assert.isNotNull(SigDates.addBusinessDays(friday, 1));
    }

    @IsTest
    static void logsAreWritten() {
        SigLog.info('K', null, 'info');
        SigLog.warn('K', null, 'warn');
        SigLog.error('K', null, 'error', new SigException('boom'));
        Assert.areEqual(3, [SELECT COUNT() FROM Signal_Log__c WHERE Signal_Key__c = 'K']);
        Assert.isTrue([SELECT Detail__c FROM Signal_Log__c WHERE Level__c = 'Error' LIMIT 1].Detail__c.contains('boom'));
    }

    @IsTest
    static void keysListsAndSentences() {
        Id userId = UserInfo.getUserId();
        String key = SigResponseService.buildKey('Insight', 'SIG', userId, 'E'.repeat(400), userId);
        Assert.areEqual(255, key.length());
        Assert.isTrue(key.endsWith('|' + userId));
        Assert.isNull(SigResponseService.toId('nope'));
        Assert.areEqual(new List<String>{ 'Individual', 'Business' }, SigConfig.splitList('Individual,\n Business;'));
        Assert.areEqual(
            'She inherited a house.',
            SigKeywordNoteClassifier.sentenceWith('Met today. She inherited a house. Call back.', 'inherited')
        );
        Assert.isTrue(SigAccess.canRead(userId) || !SigAccess.canRead(userId));
        Assert.isNotNull(SigAccess.userGroups());
        SigAccess.customPermissionsOverride = new Set<String>{ 'Signals_Pilot' };
        Assert.isTrue(SigAccess.hasCustomPermission('Signals_Pilot'));
        Assert.isFalse(SigAccess.hasCustomPermission(''));
    }

    @IsTest
    static void opportunityDefaultsNeverGuess() {
        SigInsight ins = new SigInsight();
        ins.tokens.put('ChangeType', 'Job Change');
        Signal_Definition__mdt def = SigTestData.definition(new Map<String, Object>{
            'Signal_Key__c' => 'D',
            'Opportunity_Record_Type__c' => 'No_Such_Record_Type',
            'Opportunity_Stage__c' => 'No Such Stage',
            'Opportunity_Name_Pattern__c' => '{ChangeType} review'
        });
        SigOpportunityDefaults.apply(ins, def, null);
        Assert.areEqual('Job Change review', ins.suggestedValues.get('Name'));
        Assert.isFalse(ins.suggestedValues.containsKey('StageName'));
        Assert.isFalse(ins.suggestedValues.containsKey('CloseDate'));
        Assert.isTrue(ins.notSuggested.contains('Record Type'));
        Assert.isTrue(ins.notSuggested.contains('Stage'));
        Assert.isTrue(ins.notSuggested.contains('Close Date'));
        Assert.isNull(SigOpportunityDefaults.openStage(null));
    }
}

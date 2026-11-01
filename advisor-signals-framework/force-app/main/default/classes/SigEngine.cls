/**
 * The one evaluation service behind every surface (record page, agent panel, embedded portal).
 *
 * For a record it runs every active signal source configured for that record's object,
 * after checking the user's access, the signal's audience and the client's record type.
 * It reduces each source's results to one insight per group, suppresses a drafted
 * Opportunity when an open one already exists, fills wording and defaults from metadata,
 * then applies the advisor's earlier responses. Nothing is written by evaluation except
 * error logs.
 */
public with sharing class SigEngine {
    public static final String SURFACE_RECORD_PAGE = 'Record Page';
    public static final String SURFACE_AGENT = 'Agent';

    /**
     * @param recordId     client Account or Opportunity
     * @param agent        Insight, Next Best Action, or blank for both
     * @param surface      Record Page or Agent
     * @param explicitAsk  true when the advisor asked (agent, or a "show" click), false when pushed
     * @param sessionToken browser-session token used for session-only Not now
     */
    public static List<SigInsight> evaluate(
        Id recordId,
        String agent,
        String surface,
        Boolean explicitAsk,
        String sessionToken
    ) {
        Map<String, Signal_Definition__mdt> used = new Map<String, Signal_Definition__mdt>();
        List<SigInsight> raw = evaluateRaw(recordId, agent, surface, explicitAsk, used);
        return SigResponseService.apply(raw, used, explicitAsk, sessionToken);
    }

    /** True when the signal with this response key still applies. Called just before saving. */
    public static Boolean recheck(Id recordId, String responseKey) {
        if (recordId == null || String.isBlank(responseKey)) {
            return false;
        }
        for (SigInsight ins : evaluateRaw(recordId, null, SURFACE_RECORD_PAGE, true, new Map<String, Signal_Definition__mdt>())) {
            if (ins.responseKey == responseKey) {
                return true;
            }
        }
        return false;
    }

    /** The live insight with this response key, ignoring earlier responses; null if it no longer applies. */
    public static SigInsight findInsight(Id recordId, String responseKey) {
        if (recordId == null || String.isBlank(responseKey)) {
            return null;
        }
        for (SigInsight ins : evaluateRaw(recordId, null, SURFACE_AGENT, true, new Map<String, Signal_Definition__mdt>())) {
            if (ins.responseKey == responseKey) {
                return ins;
            }
        }
        return null;
    }

    @TestVisible
    static List<SigInsight> evaluateRaw(
        Id recordId,
        String agent,
        String surface,
        Boolean explicitAsk,
        Map<String, Signal_Definition__mdt> usedDefinitions
    ) {
        List<SigInsight> result = new List<SigInsight>();
        if (recordId == null) {
            return result;
        }
        String anchorObject = recordId.getSObjectType().getDescribe().getName();
        List<Signal_Definition__mdt> definitions = SigConfig.activeDefinitions(anchorObject, agent);
        if (definitions.isEmpty() || !SigAccess.canRead(recordId)) {
            return result;
        }
        SigRecordInfo info = SigRecordInfo.load(recordId);
        if (info == null) {
            return result;
        }
        Set<String> groups = SigAccess.userGroups();

        for (Signal_Definition__mdt def : definitions) {
            if (!SigConfig.audienceAllows(def.Signal_Key__c, groups)) {
                continue;
            }
            if (!SigConfig.recordTypeIncluded(def, info.clientRecordType)) {
                continue;
            }
            usedDefinitions.put(def.Signal_Key__c, def);

            List<SigInsight> found;
            try {
                SigSource source = SigConfig.sourceFor(def);
                found = source.evaluate(new SigContext(recordId, def, groups, surface, explicitAsk));
            } catch (Exception e) {
                // One failing signal never blocks the others.
                SigLog.error(def.Signal_Key__c, recordId, 'Signal evaluation failed.', e);
                continue;
            }
            if (found == null || found.isEmpty()) {
                continue;
            }
            if (def.Primary_Action__c == 'Draft Opportunity' && SigGuards.hasOpenOpportunity(info.clientId, def.Opportunity_Record_Type__c)) {
                continue;
            }
            for (SigInsight ins : pickBest(found)) {
                decorate(ins, def, info, recordId);
                result.add(ins);
            }
        }
        return result;
    }

    /** One insight per group: the highest rank wins, then the newest evidence. */
    @TestVisible
    static List<SigInsight> pickBest(List<SigInsight> found) {
        Map<String, SigInsight> best = new Map<String, SigInsight>();
        List<String> order = new List<String>();
        for (SigInsight ins : found) {
            if (ins == null) {
                continue;
            }
            String groupKey = ins.dedupeGroup != null ? ins.dedupeGroup : (ins.changeType != null ? ins.changeType : '');
            SigInsight current = best.get(groupKey);
            if (current == null) {
                best.put(groupKey, ins);
                order.add(groupKey);
            } else if (beats(ins, current)) {
                best.put(groupKey, ins);
            }
        }
        List<SigInsight> out = new List<SigInsight>();
        for (String key : order) {
            out.add(best.get(key));
        }
        return out;
    }

    private static Boolean beats(SigInsight a, SigInsight b) {
        Integer rankA = a.rank == null ? 0 : a.rank;
        Integer rankB = b.rank == null ? 0 : b.rank;
        if (rankA != rankB) {
            return rankA > rankB;
        }
        if (a.evidenceDate == null) {
            return false;
        }
        return b.evidenceDate == null || a.evidenceDate > b.evidenceDate;
    }

    private static void decorate(SigInsight ins, Signal_Definition__mdt def, SigRecordInfo info, Id recordId) {
        ins.signalKey = def.Signal_Key__c;
        ins.agent = def.Agent__c;
        ins.anchorId = recordId;
        if (ins.clientId == null && info.clientId != null) {
            ins.clientId = info.clientId;
        }
        if (ins.opportunityId == null && recordId.getSObjectType() == Opportunity.SObjectType) {
            ins.opportunityId = recordId;
        }
        ins.primaryAction = def.Primary_Action__c;
        ins.primaryLabel = String.isBlank(def.Primary_Action_Label__c) ? def.Primary_Action__c : def.Primary_Action_Label__c;
        ins.secondaryLabel = String.isBlank(def.Secondary_Action_Label__c) ? 'Not now' : def.Secondary_Action_Label__c;
        ins.allowTask = def.Allow_Task__c == true;

        putIfMissing(ins.tokens, 'ClientName', info.clientName);
        putIfMissing(ins.tokens, 'Date', SigTokens.formatDate(ins.evidenceDate));
        putIfMissing(ins.tokens, 'Source', ins.source);
        putIfMissing(ins.tokens, 'ChangeType', ins.changeType);
        putIfMissing(ins.tokens, 'Confidence', ins.confidence);

        if (def.Primary_Action__c == 'Draft Opportunity') {
            SigOpportunityDefaults.apply(ins, def, info);
        }
        if (String.isBlank(ins.prompt)) {
            ins.prompt = SigTokens.fill(def.Prompt_Template__c, ins.tokens);
        }
        if (def.Primary_Action__c == 'Draft Opportunity' && !ins.suggestedValues.containsKey('Description')) {
            ins.suggestedValues.put('Description', describe(ins));
        }
        String evidenceKey = String.isNotBlank(ins.evidenceId)
            ? ins.evidenceId
            : (ins.evidenceDate != null ? String.valueOf(ins.evidenceDate) : 'none');
        ins.responseKey = SigResponseService.buildKey(def.Agent__c, def.Signal_Key__c, recordId, evidenceKey, UserInfo.getUserId());
    }

    /** Opportunity description: the change, its evidence, source, date and confidence label. */
    private static String describe(SigInsight ins) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(ins.changeType)) {
            parts.add(ins.changeType + '.');
        }
        if (String.isNotBlank(ins.evidenceSummary)) {
            parts.add(ins.evidenceSummary + '.');
        }
        String sourceLine = 'Source: ' + (String.isBlank(ins.source) ? 'not recorded' : ins.source);
        if (ins.evidenceDate != null) {
            sourceLine += ', ' + ins.evidenceDate.format();
        }
        if (String.isNotBlank(ins.confidence)) {
            sourceLine += ' (' + ins.confidence + ')';
        }
        parts.add(sourceLine + '.');
        return String.join(parts, ' ').left(32000);
    }

    private static void putIfMissing(Map<String, String> tokens, String key, String value) {
        if (!tokens.containsKey(key) && value != null) {
            tokens.put(key, value);
        }
    }
}

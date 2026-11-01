/**
 * Everything a SigSource needs to evaluate one signal on one record.
 */
public with sharing class SigContext {
    public Id recordId { get; private set; }
    public String anchorObject { get; private set; }
    public Signal_Definition__mdt definition { get; private set; }
    public Set<String> userGroups { get; private set; }
    public String surface { get; private set; }
    public Boolean explicitAsk { get; private set; }
    public Date today { get; private set; }
    public Id userId { get; private set; }

    public SigContext(
        Id recordId,
        Signal_Definition__mdt definition,
        Set<String> userGroups,
        String surface,
        Boolean explicitAsk
    ) {
        this.recordId = recordId;
        this.anchorObject = recordId.getSObjectType().getDescribe().getName();
        this.definition = definition;
        this.userGroups = userGroups == null ? new Set<String>() : userGroups;
        this.surface = surface;
        this.explicitAsk = explicitAsk == true;
        this.today = SigClock.today();
        this.userId = UserInfo.getUserId();
    }

    public String signalKey() {
        return definition.Signal_Key__c;
    }

    public Integer lookbackDays() {
        return definition.Lookback_Days__c == null ? 90 : definition.Lookback_Days__c.intValue();
    }

    public Date lookbackStart() {
        return today.addDays(-lookbackDays());
    }

    /** Parameters for this signal that match the record's context; see SigConfig.resolveRule. */
    public SigConfig.Rule rule(String recordType, String stage, String segment) {
        return SigConfig.resolveRule(definition, userGroups, recordType, stage, segment);
    }

    /** A new insight already tied to this signal and record. */
    public SigInsight newInsight() {
        SigInsight ins = new SigInsight();
        ins.signalKey = definition.Signal_Key__c;
        ins.anchorId = recordId;
        return ins;
    }
}

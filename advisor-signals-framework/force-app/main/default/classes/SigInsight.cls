/**
 * One signal found for one record, as shown on a card.
 *
 * Sources fill the evidence fields (changeType, evidenceId, evidenceDate, source,
 * confidence, tokens, suggestedValues). The engine fills the rest (labels, prompt,
 * responseKey, Opportunity defaults) from Signal_Definition__mdt.
 */
public with sharing class SigInsight {
    @AuraEnabled
    public String signalKey;
    @AuraEnabled
    public String agent;
    @AuraEnabled
    public String anchorId;
    @AuraEnabled
    public String clientId;
    @AuraEnabled
    public String opportunityId;

    /** The specific change or reason within the signal, e.g. Job Change. */
    @AuraEnabled
    public String changeType;
    /** Id or key of the record that raised the signal; part of the response key. */
    @AuraEnabled
    public String evidenceId;
    @AuraEnabled
    public Date evidenceDate;
    /** One line describing the evidence, e.g. a quoted sentence from a note. */
    @AuraEnabled
    public String evidenceSummary;
    /** Where the evidence came from, e.g. Profile history, Interaction note. */
    @AuraEnabled
    public String source;
    /** Confirmed, Inferred or Unconfirmed. Wording should follow this label. */
    @AuraEnabled
    public String confidence;
    /** Normal or High. */
    @AuraEnabled
    public String priority = 'Normal';

    @AuraEnabled
    public String prompt;
    @AuraEnabled
    public String reminderText;
    @AuraEnabled
    public String primaryAction;
    @AuraEnabled
    public String primaryLabel;
    @AuraEnabled
    public String secondaryLabel;
    @AuraEnabled
    public Boolean allowTask = false;
    @AuraEnabled
    public String responseKey;

    /** Field API name to suggested value, shown pre-filled and editable in the form. */
    @AuraEnabled
    public Map<String, Object> suggestedValues = new Map<String, Object>();
    /** Field labels that could not be suggested; the card tells the advisor. */
    @AuraEnabled
    public List<String> notSuggested = new List<String>();

    /** Values for {Token} placeholders in the prompt and name pattern. Not sent to the browser. */
    public Map<String, String> tokens = new Map<String, String>();
    /** Higher rank wins when a source returns several insights in the same group. */
    public Integer rank = 0;
    /** Insights with the same group are reduced to one. Defaults to changeType. */
    public String dedupeGroup;
}

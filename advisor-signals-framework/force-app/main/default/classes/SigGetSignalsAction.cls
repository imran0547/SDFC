/**
 * Agent action "Get Signals": evaluates the signals for a record and returns them as text
 * for the agent to reason over (which signal, its response key, wording, evidence). Use
 * "Show Signals" (SigAgentAction) to display them as cards. Never changes data.
 */
public with sharing class SigGetSignalsAction {
    public class Request {
        @InvocableVariable(label='Record Id' description='Client (Account) or Opportunity.' required=true)
        public String recordId;

        @InvocableVariable(label='Agent' description='Insight or Next Best Action. Leave blank for both.')
        public String agent;
    }

    public class Response {
        @InvocableVariable(label='Count')
        public Integer count;

        @InvocableVariable(label='Signals' description='One block per signal: number, response key, change type, sentence, evidence, reminder.')
        public String signalsText;

        @InvocableVariable(label='Response Keys' description='Response keys in the same order, for Get Follow-ups, Create Follow-up and Record Signal Response.')
        public List<String> responseKeys;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Get Signals' description='Returns the signals for a client or Opportunity as text, including skipped ones with a reminder. Never changes data.')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.responseKeys = new List<String>();
            try {
                List<SigInsight> insights = SigEngine.evaluate(Id.valueOf(req.recordId), req.agent, SigEngine.SURFACE_AGENT, true, null);
                res.count = insights.size();
                res.signalsText = describe(insights);
                for (SigInsight ins : insights) {
                    res.responseKeys.add(ins.responseKey);
                }
                res.message = insights.isEmpty() ? 'There are no signals for this record right now.' : null;
            } catch (Exception e) {
                SigLog.error(null, null, 'Get Signals failed for ' + req.recordId, e);
                res.count = 0;
                res.message = 'I can\'t check this record right now. Please try again shortly.';
            }
            responses.add(res);
        }
        return responses;
    }

    @TestVisible
    static String describe(List<SigInsight> insights) {
        List<String> blocks = new List<String>();
        Integer i = 1;
        for (SigInsight ins : insights) {
            List<String> lines = new List<String>{
                i + '. ' + (ins.changeType == null ? 'Signal' : ins.changeType) + (ins.confidence == null ? '' : ' (' + ins.confidence + ')'),
                'Response key: ' + ins.responseKey,
                'Sentence: ' + ins.prompt
            };
            if (String.isNotBlank(ins.source) || ins.evidenceDate != null) {
                lines.add('Evidence: ' + (ins.source == null ? '' : ins.source) + (ins.evidenceDate == null ? '' : ', ' + ins.evidenceDate.format()));
            }
            if (String.isNotBlank(ins.evidenceSummary)) {
                lines.add('Quote: ' + ins.evidenceSummary);
            }
            if (String.isNotBlank(ins.reminderText)) {
                lines.add('Reminder: ' + ins.reminderText);
            }
            lines.add('Primary action: ' + ins.primaryLabel);
            blocks.add(String.join(lines, '\n'));
            i++;
        }
        return String.join(blocks, '\n\n');
    }
}

/**
 * Agent action "Show Signals": evaluates the configured signals for a record and returns
 * them as cards (for the Lightning Type renderer) and as plain text (for channels without
 * cards). It never saves anything; the card buttons open the advisor's own forms.
 */
public with sharing class SigAgentAction {
    public class Request {
        @InvocableVariable(label='Record Id' description='Client (Account) or Opportunity the advisor is asking about.' required=true)
        public String recordId;

        @InvocableVariable(label='Agent' description='Insight or Next Best Action. Leave blank to return both.')
        public String agent;
    }

    public class Response {
        @InvocableVariable(label='Cards JSON' description='Signal cards, rendered by the sigInsightList component.')
        public String cardsJson;

        @InvocableVariable(label='Summary' description='Plain-text summary for channels that cannot show cards.')
        public String summary;

        @InvocableVariable(label='Count' description='Number of signals found.')
        public Integer count;
    }

    @InvocableMethod(
        label='Show Signals'
        description='Evaluates the configured signals for a client or Opportunity and returns cards. Never creates or updates records.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            try {
                Id recordId = Id.valueOf(req.recordId);
                List<SigInsight> insights = SigEngine.evaluate(recordId, req.agent, SigEngine.SURFACE_AGENT, true, null);
                res.cardsJson = JSON.serialize(insights);
                res.count = insights.size();
                res.summary = summarize(insights);
            } catch (Exception e) {
                SigLog.error(null, null, 'Agent action failed for record ' + req.recordId, e);
                res.cardsJson = '[]';
                res.count = 0;
                res.summary = 'I can\'t check this record right now. Please try again shortly.';
            }
            responses.add(res);
        }
        return responses;
    }

    @TestVisible
    static String summarize(List<SigInsight> insights) {
        if (insights.isEmpty()) {
            return 'There are no signals for this record right now.';
        }
        List<String> lines = new List<String>();
        for (SigInsight ins : insights) {
            String line = '- ' + ins.prompt;
            if (String.isNotBlank(ins.reminderText)) {
                line += ' (' + ins.reminderText + ')';
            }
            lines.add(line);
        }
        return String.join(lines, '\n');
    }
}

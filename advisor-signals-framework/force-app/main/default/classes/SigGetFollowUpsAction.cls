/**
 * Agent action "Get Follow-ups": which follow-ups are allowed for a signal (from its
 * definition), typically after the advisor saved the Opportunity. Never changes data.
 */
public with sharing class SigGetFollowUpsAction {
    public class Request {
        @InvocableVariable(label='Record Id' description='Client or Opportunity the signal was shown for.' required=true)
        public String recordId;

        @InvocableVariable(label='Response Key' description='Response key of the signal, from Get Signals or the card.' required=true)
        public String responseKey;
    }

    public class Response {
        @InvocableVariable(label='Options' description='Allowed follow-ups, e.g. Task. Empty when none.')
        public List<String> options;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Get Follow-ups' description='Lists the follow-ups allowed for a signal. Never changes data.')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.options = new List<String>();
            try {
                SigFollowUpService.Resolved r = SigFollowUpService.resolve(SigResponseService.toId(req.recordId), req.responseKey);
                if (r == null) {
                    res.message = 'That signal no longer applies, so there is nothing to follow up.';
                } else if (r.insight.allowTask == true) {
                    res.options.add('Task');
                    res.message = 'I can prepare a follow-up Task for you to review and save.';
                } else {
                    res.message = 'No follow-ups are set up for this signal.';
                }
            } catch (Exception e) {
                SigLog.error(null, null, 'Get Follow-ups failed for ' + req.recordId, e);
                res.message = 'I can\'t check follow-ups right now. Please try again shortly.';
            }
            responses.add(res);
        }
        return responses;
    }
}

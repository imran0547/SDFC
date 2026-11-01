/**
 * Agent action "Show Past Signal Responses": the advisor's own earlier responses
 * (Not Now, Acted On) for a client or Opportunity, newest first. Never changes data.
 */
public with sharing class SigPastResponsesAction {
    public class Request {
        @InvocableVariable(label='Record Id' description='Client (Account) or Opportunity.' required=true)
        public String recordId;
    }

    public class Response {
        @InvocableVariable(label='Count')
        public Integer count;

        @InvocableVariable(label='Responses' description='One line per response: date, status, change type, sentence.')
        public String responsesText;
    }

    @InvocableMethod(label='Show Past Signal Responses' description='Lists the advisor\'s earlier responses to signals for a record. Never changes data.')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        Id userId = UserInfo.getUserId();
        for (Request req : requests) {
            Response res = new Response();
            res.count = 0;
            try {
                Id recordId = Id.valueOf(req.recordId);
                List<String> lines = new List<String>();
                for (Signal_Response__c r : [
                    SELECT Responded_At__c, Status__c, Change_Type__c, Prompt__c
                    FROM Signal_Response__c
                    WHERE Responded_By__c = :userId AND (Client__c = :recordId OR Opportunity__c = :recordId)
                    WITH USER_MODE
                    ORDER BY Responded_At__c DESC
                    LIMIT 10
                ]) {
                    lines.add(
                        (r.Responded_At__c == null ? '' : r.Responded_At__c.date().format()) + ' – ' + r.Status__c +
                        (r.Change_Type__c == null ? '' : ' – ' + r.Change_Type__c) +
                        (r.Prompt__c == null ? '' : ': ' + r.Prompt__c)
                    );
                }
                res.count = lines.size();
                res.responsesText = lines.isEmpty() ? 'You have not responded to any signals for this record.' : String.join(lines, '\n');
            } catch (Exception e) {
                SigLog.error(null, null, 'Past responses failed for ' + req.recordId, e);
                res.responsesText = 'I can\'t read your earlier responses right now. Please try again shortly.';
            }
            responses.add(res);
        }
        return responses;
    }
}

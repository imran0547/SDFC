/**
 * Agent action "Record Signal Response": stores the advisor's Not Now when they decline a
 * signal in conversation. Acted On is recorded by the card after a successful save.
 */
public with sharing class SigRecordResponseAction {
    public class Request {
        @InvocableVariable(label='Record Id' description='Client or Opportunity the signal was shown for.' required=true)
        public String recordId;

        @InvocableVariable(label='Response Key' description='responseKey of the signal, from the Show Signals cards.' required=true)
        public String responseKey;
    }

    public class Response {
        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Saved')
        public Boolean saved;
    }

    @InvocableMethod(label='Record Signal Not Now' description='Hides a signal for the advisor according to its Not now settings. Changes nothing else.')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.saved = false;
            try {
                Id recordId = Id.valueOf(req.recordId);
                SigInsight match = null;
                for (SigInsight ins : SigEngine.evaluate(recordId, null, SigEngine.SURFACE_AGENT, true, null)) {
                    if (ins.responseKey == req.responseKey) {
                        match = ins;
                        break;
                    }
                }
                if (match == null) {
                    res.message = 'That signal no longer applies, so there is nothing to skip.';
                } else {
                    SigResponseService.record(match, SigResponseService.NOT_NOW, SigEngine.SURFACE_AGENT, null, null);
                    res.saved = true;
                    res.message = 'Okay, I\'ve skipped it for now.';
                }
            } catch (Exception e) {
                SigLog.error(null, null, 'Not now could not be saved for ' + req.recordId, e);
                res.message = 'I couldn\'t save that. Nothing was changed.';
            }
            responses.add(res);
        }
        return responses;
    }
}

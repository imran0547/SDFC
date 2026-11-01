/**
 * Agent action "Create Follow-up": prepares a pre-filled follow-up Task for the advisor to
 * review and save. It returns a draft (rendered as a card by the sigFollowUpDraft Lightning
 * Type); it never saves the Task itself.
 */
public with sharing class SigCreateFollowUpAction {
    public class Request {
        @InvocableVariable(label='Record Id' description='Client or Opportunity the signal was shown for.' required=true)
        public String recordId;

        @InvocableVariable(label='Response Key' description='Response key of the signal.' required=true)
        public String responseKey;

        @InvocableVariable(label='Follow-up Type' description='Task (the only type in this version).')
        public String followUpType;
    }

    public class Response {
        @InvocableVariable(label='Draft JSON' description='Pre-filled form for the follow-up card: objectApiName, heading, fields, responseKey.')
        public String draftJson;

        @InvocableVariable(label='Summary' description='Plain-text summary of the draft for channels without cards.')
        public String summary;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Create Follow-up' description='Prepares a pre-filled follow-up Task for the advisor to review and save. Does not save it.')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            try {
                if (String.isNotBlank(req.followUpType) && !'Task'.equalsIgnoreCase(req.followUpType)) {
                    res.message = 'Only a follow-up Task is available.';
                    responses.add(res);
                    continue;
                }
                SigFollowUpService.Resolved r = SigFollowUpService.resolve(SigResponseService.toId(req.recordId), req.responseKey);
                if (r == null) {
                    res.message = 'That signal no longer applies, so there is nothing to follow up.';
                } else if (r.insight.allowTask != true) {
                    res.message = 'No follow-up Task is set up for this signal.';
                } else {
                    Map<String, Object> values = SigFollowUpService.taskDefaults(r.insight, r.whatId);
                    List<Map<String, Object>> fields = new List<Map<String, Object>>();
                    for (String name : new List<String>{ 'Subject', 'ActivityDate', 'Priority', 'WhoId', 'WhatId', 'OwnerId', 'Description' }) {
                        if (values.containsKey(name)) {
                            fields.add(new Map<String, Object>{ 'fieldName' => name, 'value' => values.get(name) });
                        }
                    }
                    res.draftJson = JSON.serialize(new Map<String, Object>{
                        'objectApiName' => 'Task',
                        'heading' => 'Create a Task',
                        'responseKey' => req.responseKey,
                        'fields' => fields
                    });
                    res.summary = 'Task "' + String.valueOf(values.get('Subject')) + '", due ' + String.valueOf(values.get('ActivityDate')) + '.';
                    res.message = 'Here is a follow-up Task to review. It is saved only when you click Save.';
                }
            } catch (Exception e) {
                SigLog.error(null, null, 'Create Follow-up failed for ' + req.recordId, e);
                res.message = 'I can\'t prepare the Task right now. You can create it manually.';
            }
            responses.add(res);
        }
        return responses;
    }
}

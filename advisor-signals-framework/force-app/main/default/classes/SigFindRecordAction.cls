/**
 * Agent action "Identify Record by Name": finds the client (or Opportunity) the advisor
 * named, among records the advisor can see. With several matches it lists them so the
 * agent can ask which one.
 */
public with sharing class SigFindRecordAction {
    public class Request {
        @InvocableVariable(label='Name' description='Name, or part of the name, the advisor used.' required=true)
        public String name;

        @InvocableVariable(label='Object' description='Account (default) or Opportunity.')
        public String objectName;
    }

    public class Response {
        @InvocableVariable(label='Record Id' description='Set when exactly one record matches.')
        public String recordId;

        @InvocableVariable(label='Match Count')
        public Integer matchCount;

        @InvocableVariable(label='Matches' description='Up to five matches, one per line: Name (Id).')
        public String matchesText;

        @InvocableVariable(label='Message' description='What to tell the advisor.')
        public String message;
    }

    @InvocableMethod(label='Identify Record by Name' description='Finds a client or Opportunity by name among records the advisor can see. Never changes data.')
    public static List<Response> run(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            responses.add(find(req));
        }
        return responses;
    }

    private static Response find(Request req) {
        Response res = new Response();
        res.matchCount = 0;
        String name = req.name == null ? '' : req.name.trim();
        if (name.length() < 2) {
            res.message = 'Which client do you mean? Please give me at least two letters of the name.';
            return res;
        }
        String objectName = 'Opportunity'.equalsIgnoreCase(req.objectName) ? 'Opportunity' : 'Account';
        String term = '%' + name.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
        List<SObject> rows = Database.queryWithBinds(
            'SELECT Id, Name FROM ' + objectName + ' WHERE Name LIKE :term ORDER BY LastModifiedDate DESC LIMIT 6',
            new Map<String, Object>{ 'term' => term },
            AccessLevel.USER_MODE
        );
        List<SObject> exact = new List<SObject>();
        for (SObject row : rows) {
            if (name.equalsIgnoreCase((String) row.get('Name'))) {
                exact.add(row);
            }
        }
        List<SObject> matches = exact.size() == 1 ? exact : rows;
        res.matchCount = matches.size();
        if (matches.isEmpty()) {
            res.message = 'I couldn\'t find a ' + (objectName == 'Account' ? 'client' : 'Opportunity') + ' named "' + name + '" that you can access.';
        } else if (matches.size() == 1) {
            res.recordId = (Id) matches[0].get('Id');
            res.message = 'Found ' + (String) matches[0].get('Name') + '.';
        } else {
            List<String> lines = new List<String>();
            for (Integer i = 0; i < Math.min(matches.size(), 5); i++) {
                lines.add((String) matches[i].get('Name') + ' (' + (Id) matches[i].get('Id') + ')');
            }
            res.matchesText = String.join(lines, '\n');
            res.message = 'Several records match "' + name + '". Which one do you mean?';
        }
        return res;
    }
}

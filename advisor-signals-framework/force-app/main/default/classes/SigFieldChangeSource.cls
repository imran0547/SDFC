/**
 * Sample Insight source: a tracked client field changed recently (for example an employer
 * field, which may indicate a job change). Reads Account field history.
 *
 * Parameters (Signal_Parameter__mdt):
 *   Tracked_Field    Text  Account field API name; field history tracking must be on
 *   Change_Type      Text  label for the change, e.g. Job Change
 *   Match_Pattern    Text  optional regular expression the new value must match
 *   Exclude_Pattern  Text  optional regular expression that rules a new value out
 *
 * A change that only fixes spelling, case, punctuation or a company suffix (Inc, LLC...)
 * is ignored.
 */
public with sharing class SigFieldChangeSource implements SigSource {
    public interface HistoryProvider {
        List<Change> changes(Id accountId, String fieldName, Datetime since);
    }

    public class Change {
        public String id;
        public Object oldValue;
        public Object newValue;
        public Datetime changedAt;

        public Change(String id, Object oldValue, Object newValue, Datetime changedAt) {
            this.id = id;
            this.oldValue = oldValue;
            this.newValue = newValue;
            this.changedAt = changedAt;
        }
    }

    @TestVisible
    static HistoryProvider provider = new AccountHistoryProvider();

    public List<SigInsight> evaluate(SigContext ctx) {
        List<SigInsight> out = new List<SigInsight>();
        if (ctx.recordId.getSObjectType() != Account.SObjectType) {
            return out;
        }
        SigConfig.Rule rule = ctx.rule(null, null, null);
        String field = rule.getText('Tracked_Field');
        if (String.isBlank(field)) {
            SigLog.warn(ctx.signalKey(), ctx.recordId, 'Tracked_Field parameter is not set.');
            return out;
        }
        String changeType = rule.has('Change_Type') ? rule.getText('Change_Type') : 'Profile Change';
        String matchPattern = rule.getText('Match_Pattern');
        String excludePattern = rule.getText('Exclude_Pattern');
        Datetime since = Datetime.newInstance(ctx.lookbackStart(), Time.newInstance(0, 0, 0, 0));

        for (Change c : provider.changes(ctx.recordId, field, since)) {
            String oldValue = c.oldValue == null ? '' : String.valueOf(c.oldValue);
            String newValue = c.newValue == null ? '' : String.valueOf(c.newValue);
            if (String.isBlank(newValue) || normalize(oldValue) == normalize(newValue)) {
                continue;
            }
            if (String.isNotBlank(matchPattern) && !Pattern.compile('(?i)' + matchPattern).matcher(newValue).find()) {
                continue;
            }
            if (String.isNotBlank(excludePattern) && Pattern.compile('(?i)' + excludePattern).matcher(newValue).find()) {
                continue;
            }
            SigInsight ins = ctx.newInsight();
            ins.clientId = ctx.recordId;
            ins.changeType = changeType;
            ins.evidenceId = c.id;
            ins.evidenceDate = c.changedAt == null ? null : c.changedAt.date();
            ins.source = 'Profile history';
            ins.confidence = 'Confirmed';
            ins.evidenceSummary = 'Changed from "' + oldValue + '" to "' + newValue + '"';
            ins.tokens.put('Change', changeType);
            ins.tokens.put('OldValue', oldValue);
            ins.tokens.put('NewValue', newValue);
            out.add(ins);
            break; // newest qualifying change only
        }
        return out;
    }

    /** Lower case, no punctuation, no trailing company suffix, single spaces. */
    @TestVisible
    static String normalize(String value) {
        if (value == null) {
            return '';
        }
        String s = value.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').normalizeSpace();
        s = s.replaceAll('\\s+(inc|incorporated|llc|ltd|limited|corp|corporation|co|company|plc)$', '');
        return s.normalizeSpace();
    }

    /** Default provider: Account field history, read as the user. */
    public class AccountHistoryProvider implements HistoryProvider {
        public List<Change> changes(Id accountId, String fieldName, Datetime since) {
            List<Change> out = new List<Change>();
            if (!Schema.SObjectType.Account.fields.getMap().containsKey(fieldName.toLowerCase())) {
                SigLog.warn(null, accountId, 'Tracked field not found on Account: ' + fieldName);
                return out;
            }
            for (AccountHistory h : [
                SELECT Id, OldValue, NewValue, CreatedDate
                FROM AccountHistory
                WHERE AccountId = :accountId AND Field = :fieldName AND CreatedDate >= :since
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 50
            ]) {
                out.add(new Change(h.Id, h.OldValue, h.NewValue, h.CreatedDate));
            }
            return out;
        }
    }
}

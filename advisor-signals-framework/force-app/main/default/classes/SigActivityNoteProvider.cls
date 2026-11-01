/**
 * Default note provider: descriptions of the client's Tasks and Events, newest first,
 * read as the user. Works in any org; replace it with your own note store if you have one.
 */
public with sharing class SigActivityNoteProvider implements SigNoteProvider {
    public List<SigNote> notes(Id clientId, Date since, Integer maxNotes) {
        List<SigNote> out = new List<SigNote>();
        if (clientId == null) {
            return out;
        }
        Integer cap = maxNotes == null || maxNotes <= 0 ? 20 : maxNotes;
        Datetime sinceTime = Datetime.newInstance(since, Time.newInstance(0, 0, 0, 0));
        // Long text fields cannot be filtered in SOQL, so blank descriptions are skipped here.
        for (Task t : [
            SELECT Id, Description, ActivityDate, CreatedDate
            FROM Task
            WHERE AccountId = :clientId AND CreatedDate >= :sinceTime
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :cap
        ]) {
            if (String.isNotBlank(t.Description)) {
                out.add(new SigNote(t.Id, t.ActivityDate != null ? t.ActivityDate : t.CreatedDate.date(), t.Description));
            }
        }
        for (Event e : [
            SELECT Id, Description, ActivityDate, CreatedDate
            FROM Event
            WHERE AccountId = :clientId AND CreatedDate >= :sinceTime
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :cap
        ]) {
            if (String.isNotBlank(e.Description)) {
                out.add(new SigNote(e.Id, e.ActivityDate != null ? e.ActivityDate : e.CreatedDate.date(), e.Description));
            }
        }
        return newestFirst(out, cap);
    }

    private static List<SigNote> newestFirst(List<SigNote> notes, Integer cap) {
        List<SigNote> sorted = new List<SigNote>();
        List<SigNote> remaining = new List<SigNote>(notes);
        while (!remaining.isEmpty() && sorted.size() < cap) {
            Integer newest = 0;
            for (Integer i = 1; i < remaining.size(); i++) {
                Date candidate = remaining.get(i).noteDate;
                Date current = remaining.get(newest).noteDate;
                if (candidate != null && (current == null || candidate > current)) {
                    newest = i;
                }
            }
            sorted.add(remaining.remove(newest));
        }
        return sorted;
    }
}

/**
 * Supplies recent notes for a client. Implement this for your note store (for example
 * meeting-note or interaction-summary objects) and name the class in the
 * Note_Provider_Class parameter. The default reads Task and Event descriptions.
 */
public interface SigNoteProvider {
    List<SigNote> notes(Id clientId, Date since, Integer maxNotes);
}

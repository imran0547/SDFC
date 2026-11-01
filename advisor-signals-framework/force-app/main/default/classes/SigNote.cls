/**
 * A free-text note about a client, from any note store (activities, meeting notes...).
 */
public with sharing class SigNote {
    public String id;
    public Date noteDate;
    public String text;

    public SigNote(String id, Date noteDate, String text) {
        this.id = id;
        this.noteDate = noteDate;
        this.text = text;
    }
}

/**
 * A classifier's reading of one note.
 * strength: Strong (enough on its own), Weak (needs a second signal), Excluded or None.
 */
public with sharing class SigNoteVerdict {
    public static final String STRONG = 'Strong';
    public static final String WEAK = 'Weak';
    public static final String EXCLUDED = 'Excluded';
    public static final String NONE = 'None';

    public SigNote note;
    public String strength;
    /** The sentence that supports the verdict, quoted to the advisor. */
    public String quote;
    /** Optional: Confirmed, Unconfirmed or Inferred. */
    public String confidence;
    /** Optional: change type the classifier recognized. */
    public String changeType;

    public SigNoteVerdict(SigNote note, String strength, String quote) {
        this.note = note;
        this.strength = strength;
        this.quote = quote;
    }
}

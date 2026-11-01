/**
 * Default note classifier using configured phrase lists (no AI).
 *
 * Parameters: Strong_Phrases, Weak_Phrases, Exclude_Phrases, each separated by | or new lines.
 * An excluded phrase anywhere in the note rules the note out (for example a hypothetical
 * or a change that was reversed). Otherwise a strong phrase makes the note Strong and a
 * weak phrase makes it Weak. The quoted sentence is the one that contains the phrase.
 */
public with sharing class SigKeywordNoteClassifier implements SigNoteClassifier {
    public List<SigNoteVerdict> classify(List<SigNote> notes, SigConfig.Rule rule) {
        List<String> strong = lower(rule.getList('Strong_Phrases'));
        List<String> weak = lower(rule.getList('Weak_Phrases'));
        List<String> excluded = lower(rule.getList('Exclude_Phrases'));
        List<SigNoteVerdict> out = new List<SigNoteVerdict>();
        for (SigNote n : notes) {
            String text = n.text == null ? '' : n.text;
            String lowered = text.toLowerCase();
            if (firstMatch(lowered, excluded) != null) {
                out.add(new SigNoteVerdict(n, SigNoteVerdict.EXCLUDED, null));
                continue;
            }
            String phrase = firstMatch(lowered, strong);
            if (phrase != null) {
                out.add(new SigNoteVerdict(n, SigNoteVerdict.STRONG, sentenceWith(text, phrase)));
                continue;
            }
            phrase = firstMatch(lowered, weak);
            if (phrase != null) {
                out.add(new SigNoteVerdict(n, SigNoteVerdict.WEAK, sentenceWith(text, phrase)));
                continue;
            }
            out.add(new SigNoteVerdict(n, SigNoteVerdict.NONE, null));
        }
        return out;
    }

    private static List<String> lower(List<String> values) {
        List<String> out = new List<String>();
        for (String v : values) {
            out.add(v.toLowerCase());
        }
        return out;
    }

    private static String firstMatch(String lowered, List<String> phrases) {
        for (String p : phrases) {
            if (lowered.contains(p)) {
                return p;
            }
        }
        return null;
    }

    @TestVisible
    static String sentenceWith(String text, String phrase) {
        for (String sentence : text.split('(?<=[.!?])\\s+')) {
            if (sentence.toLowerCase().contains(phrase)) {
                return sentence.trim().left(500);
            }
        }
        return text.left(500);
    }
}

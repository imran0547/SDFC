/**
 * Sample Insight source for signals found in free-text notes, following "rules first,
 * AI second":
 *   1. read up to Max_Notes_Read recent notes (default 20) from the note provider;
 *   2. a keyword gate keeps at most Max_Notes_Checked notes (default 3) that mention the signal;
 *   3. the classifier (keyword lists by default, or your LLM class) reads only those notes;
 *   4. this class makes the final decision: one strong note is enough, two weak notes
 *      together count as Inferred, an excluded note never counts.
 * If the classifier fails, the failure is logged and no insight is raised from notes.
 *
 * Parameters: Change_Type, Gate_Keywords, Strong_Phrases, Weak_Phrases, Exclude_Phrases,
 * Max_Notes_Read, Max_Notes_Checked, Note_Provider_Class, Note_Classifier_Class.
 */
public with sharing class SigNoteSignalSource implements SigSource {
    @TestVisible
    static SigNoteProvider providerOverride;
    @TestVisible
    static SigNoteClassifier classifierOverride;

    public List<SigInsight> evaluate(SigContext ctx) {
        List<SigInsight> out = new List<SigInsight>();
        if (ctx.recordId.getSObjectType() != Account.SObjectType) {
            return out;
        }
        SigConfig.Rule rule = ctx.rule(null, null, null);
        Integer maxRead = rule.getInteger('Max_Notes_Read') == null ? 20 : rule.getInteger('Max_Notes_Read');
        Integer maxChecked = rule.getInteger('Max_Notes_Checked') == null ? 3 : rule.getInteger('Max_Notes_Checked');

        SigNoteProvider provider = providerOverride;
        if (provider == null && rule.has('Note_Provider_Class')) {
            provider = (SigNoteProvider) SigConfig.newInstance(rule.getText('Note_Provider_Class'));
        }
        if (provider == null) {
            provider = new SigActivityNoteProvider();
        }
        List<SigNote> notes = provider.notes(ctx.recordId, ctx.lookbackStart(), maxRead);
        List<SigNote> selected = gate(notes, rule.getList('Gate_Keywords'), maxChecked);
        if (selected.isEmpty()) {
            return out;
        }

        SigNoteClassifier classifier = classifierOverride;
        if (classifier == null && rule.has('Note_Classifier_Class')) {
            classifier = (SigNoteClassifier) SigConfig.newInstance(rule.getText('Note_Classifier_Class'));
        }
        if (classifier == null) {
            classifier = new SigKeywordNoteClassifier();
        }
        List<SigNoteVerdict> verdicts;
        try {
            verdicts = classifier.classify(selected, rule);
        } catch (Exception e) {
            SigLog.error(ctx.signalKey(), ctx.recordId, 'Note classifier failed; no insight raised from notes.', e);
            return out;
        }

        SigNoteVerdict strong = null;
        List<SigNoteVerdict> weak = new List<SigNoteVerdict>();
        for (SigNoteVerdict v : verdicts) {
            if (v == null || v.note == null) {
                continue;
            }
            if (v.strength == SigNoteVerdict.STRONG && (strong == null || newer(v, strong))) {
                strong = v;
            } else if (v.strength == SigNoteVerdict.WEAK) {
                weak.add(v);
            }
        }
        SigNoteVerdict chosen = strong;
        String confidence = strong != null ? (String.isBlank(strong.confidence) ? 'Confirmed' : strong.confidence) : null;
        if (chosen == null && weak.size() >= 2) {
            chosen = weak[0];
            for (SigNoteVerdict v : weak) {
                if (newer(v, chosen)) {
                    chosen = v;
                }
            }
            confidence = 'Inferred';
        }
        if (chosen == null) {
            return out;
        }

        String changeType = String.isNotBlank(chosen.changeType)
            ? chosen.changeType
            : (rule.has('Change_Type') ? rule.getText('Change_Type') : 'Planning Event');
        SigInsight ins = ctx.newInsight();
        ins.clientId = ctx.recordId;
        ins.changeType = changeType;
        ins.evidenceId = chosen.note.id;
        ins.evidenceDate = chosen.note.noteDate;
        ins.source = 'Advisor note';
        ins.confidence = confidence;
        ins.evidenceSummary = chosen.quote;
        ins.rank = confidence == 'Confirmed' ? 2 : 1;
        ins.tokens.put('Change', changeType);
        ins.tokens.put('Quote', chosen.quote == null ? '' : chosen.quote);
        out.add(ins);
        return out;
    }

    /** Keeps at most maxChecked notes that mention any gate keyword (all notes if none set). */
    @TestVisible
    static List<SigNote> gate(List<SigNote> notes, List<String> keywords, Integer maxChecked) {
        List<SigNote> out = new List<SigNote>();
        if (notes == null) {
            return out;
        }
        for (SigNote n : notes) {
            if (out.size() >= maxChecked) {
                break;
            }
            if (n == null || String.isBlank(n.text)) {
                continue;
            }
            if (keywords.isEmpty()) {
                out.add(n);
                continue;
            }
            String lowered = n.text.toLowerCase();
            for (String k : keywords) {
                if (lowered.contains(k.toLowerCase())) {
                    out.add(n);
                    break;
                }
            }
        }
        return out;
    }

    private static Boolean newer(SigNoteVerdict a, SigNoteVerdict b) {
        return a.note.noteDate != null && (b.note.noteDate == null || a.note.noteDate > b.note.noteDate);
    }
}

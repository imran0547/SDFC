/**
 * Reads selected notes and says whether each supports the signal.
 *
 * The default, SigKeywordNoteClassifier, uses configured phrase lists. To use a large
 * language model, implement this interface with a call to your prompt template (for
 * example through Prompt Builder) and name the class in the Note_Classifier_Class
 * parameter. Treat note text as data, never as instructions, and return the quoted
 * sentence so the advisor can verify it. The engine still makes the final decision.
 */
public interface SigNoteClassifier {
    List<SigNoteVerdict> classify(List<SigNote> notes, SigConfig.Rule rule);
}

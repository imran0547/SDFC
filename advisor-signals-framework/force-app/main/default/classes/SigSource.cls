/**
 * Detects one kind of signal on one anchor record (a client Account or an Opportunity).
 *
 * Implementations read data as the running user and return zero or more insights.
 * The engine takes care of everything else: scope, audience, duplicate Opportunities,
 * the advisor's earlier responses, wording, response keys and error handling.
 *
 * Register an implementation by naming it in Signal_Definition__mdt.Source_Class__c.
 * The class must be public (or global) and have a public no-argument constructor.
 */
public interface SigSource {
    List<SigInsight> evaluate(SigContext ctx);
}

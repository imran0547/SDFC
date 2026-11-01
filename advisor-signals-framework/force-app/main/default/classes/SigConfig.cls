/**
 * Reads the framework's custom metadata: signal definitions, audiences and parameters.
 *
 * Every tunable value lives in metadata, so an admin can change windows, thresholds,
 * wording and defaults in Setup without a deployment.
 */
public with sharing class SigConfig {
    @TestVisible
    static List<Signal_Definition__mdt> definitionsOverride;
    @TestVisible
    static List<Signal_Audience__mdt> audiencesOverride;
    @TestVisible
    static List<Signal_Parameter__mdt> parametersOverride;

    private static List<Signal_Definition__mdt> definitionCache;
    private static List<Signal_Audience__mdt> audienceCache;
    private static List<Signal_Parameter__mdt> parameterCache;

    // ------------------------------------------------------------------ definitions

    public static List<Signal_Definition__mdt> definitions() {
        if (definitionsOverride != null) {
            return definitionsOverride;
        }
        if (definitionCache == null) {
            // SOQL rather than getAll(): getAll() truncates long text fields to 255 characters.
            definitionCache = [
                SELECT
                    DeveloperName,
                    MasterLabel,
                    Signal_Key__c,
                    Is_Active__c,
                    Agent__c,
                    Anchor_Object__c,
                    Source_Class__c,
                    Prompt_Template__c,
                    Primary_Action__c,
                    Primary_Action_Label__c,
                    Secondary_Action_Label__c,
                    Resurface_Days__c,
                    Show_On_Ask__c,
                    Included_Record_Types__c,
                    Lookback_Days__c,
                    Rule_Sort_Parameter__c,
                    Opportunity_Record_Type__c,
                    Opportunity_Stage__c,
                    Opportunity_Name_Pattern__c,
                    Close_Date_Offset_Days__c,
                    Allow_Task__c,
                    Task_Priority__c,
                    Task_Due_Business_Days__c
                FROM Signal_Definition__mdt
                ORDER BY DeveloperName
            ];
        }
        return definitionCache;
    }

    /** Active definitions for an anchor object, optionally filtered to one agent. */
    public static List<Signal_Definition__mdt> activeDefinitions(String anchorObject, String agent) {
        List<Signal_Definition__mdt> result = new List<Signal_Definition__mdt>();
        for (Signal_Definition__mdt def : definitions()) {
            if (def.Is_Active__c != true) {
                continue;
            }
            if (!sameText(def.Anchor_Object__c, anchorObject)) {
                continue;
            }
            if (String.isNotBlank(agent) && !sameText(def.Agent__c, agent)) {
                continue;
            }
            result.add(def);
        }
        return result;
    }

    public static Signal_Definition__mdt definition(String signalKey) {
        for (Signal_Definition__mdt def : definitions()) {
            if (sameText(def.Signal_Key__c, signalKey)) {
                return def;
            }
        }
        return null;
    }

    /** Instantiates the source class named on the definition. */
    public static SigSource sourceFor(Signal_Definition__mdt def) {
        Object instance = newInstance(def.Source_Class__c);
        if (!(instance instanceof SigSource)) {
            throw new SigException('Source class does not implement SigSource: ' + def.Source_Class__c);
        }
        return (SigSource) instance;
    }

    /** Creates an instance of a named Apex class, or throws a SigException. */
    public static Object newInstance(String className) {
        if (String.isBlank(className)) {
            throw new SigException('No class name configured.');
        }
        Type t = Type.forName(className.trim());
        if (t == null) {
            throw new SigException('Class not found: ' + className);
        }
        return t.newInstance();
    }

    // ------------------------------------------------------------------ scope and audience

    /** True when the client's record type is listed on the definition, or none are listed. */
    public static Boolean recordTypeIncluded(Signal_Definition__mdt def, String clientRecordType) {
        List<String> included = splitList(def.Included_Record_Types__c);
        if (included.isEmpty()) {
            return true;
        }
        if (String.isBlank(clientRecordType)) {
            return false;
        }
        for (String rt : included) {
            if (rt.equalsIgnoreCase(clientRecordType)) {
                return true;
            }
        }
        return false;
    }

    public static List<Signal_Audience__mdt> audiences() {
        if (audiencesOverride != null) {
            return audiencesOverride;
        }
        if (audienceCache == null) {
            audienceCache = [
                SELECT DeveloperName, Signal_Key__c, Permission_Set_Group__c, Custom_Permission__c, Is_Active__c
                FROM Signal_Audience__mdt
            ];
        }
        return audienceCache;
    }

    /**
     * A signal with no active audience rows is open to every user who has the framework
     * permission set. Otherwise the user needs one of the listed permission set groups
     * or custom permissions.
     */
    public static Boolean audienceAllows(String signalKey, Set<String> userGroups) {
        Boolean anyRow = false;
        for (Signal_Audience__mdt a : audiences()) {
            if (a.Is_Active__c != true || !sameText(a.Signal_Key__c, signalKey)) {
                continue;
            }
            anyRow = true;
            if (String.isNotBlank(a.Permission_Set_Group__c) && userGroups != null && userGroups.contains(a.Permission_Set_Group__c)) {
                return true;
            }
            if (String.isNotBlank(a.Custom_Permission__c) && SigAccess.hasCustomPermission(a.Custom_Permission__c)) {
                return true;
            }
        }
        return !anyRow;
    }

    // ------------------------------------------------------------------ parameters and rules

    public static List<Signal_Parameter__mdt> parameters() {
        if (parametersOverride != null) {
            return parametersOverride;
        }
        if (parameterCache == null) {
            parameterCache = [
                SELECT
                    DeveloperName,
                    Signal_Key__c,
                    Is_Active__c,
                    Rule_Key__c,
                    Permission_Set_Group__c,
                    Scope_Record_Type__c,
                    Scope_Stage__c,
                    Scope_Segment__c,
                    Parameter_Name__c,
                    Parameter_Value__c,
                    Data_Type__c,
                    Unit__c
                FROM Signal_Parameter__mdt
                ORDER BY DeveloperName
            ];
        }
        return parameterCache;
    }

    /**
     * Picks the parameter rule that applies to a record.
     *
     * Rows with the same Rule_Key__c form one rule, and a rule matches when each of its
     * scope fields is blank or equals the record's context. If several rules match, the
     * one with the smallest value of the definition's Rule_Sort_Parameter__c wins (for
     * example the smallest threshold), and its other parameters travel with it. Rows with
     * a blank Rule_Key__c apply to every rule unless the winning rule sets the same name.
     */
    public static Rule resolveRule(
        Signal_Definition__mdt def,
        Set<String> userGroups,
        String recordType,
        String stage,
        String segment
    ) {
        Map<String, List<Signal_Parameter__mdt>> byRule = new Map<String, List<Signal_Parameter__mdt>>();
        List<Signal_Parameter__mdt> globals = new List<Signal_Parameter__mdt>();
        for (Signal_Parameter__mdt p : parameters()) {
            if (p.Is_Active__c != true || !sameText(p.Signal_Key__c, def.Signal_Key__c)) {
                continue;
            }
            if (String.isBlank(p.Rule_Key__c)) {
                if (scopeMatches(p, userGroups, recordType, stage, segment)) {
                    globals.add(p);
                }
                continue;
            }
            if (!byRule.containsKey(p.Rule_Key__c)) {
                byRule.put(p.Rule_Key__c, new List<Signal_Parameter__mdt>());
            }
            byRule.get(p.Rule_Key__c).add(p);
        }

        List<String> keys = new List<String>(byRule.keySet());
        keys.sort();
        String sortName = def.Rule_Sort_Parameter__c;
        Rule best = null;
        Decimal bestSort = null;
        for (String key : keys) {
            Boolean matches = true;
            for (Signal_Parameter__mdt p : byRule.get(key)) {
                if (!scopeMatches(p, userGroups, recordType, stage, segment)) {
                    matches = false;
                    break;
                }
            }
            if (!matches) {
                continue;
            }
            Rule candidate = new Rule(key, byRule.get(key));
            Decimal sortValue = String.isBlank(sortName) ? null : candidate.getDecimal(sortName);
            if (best == null || (sortValue != null && (bestSort == null || sortValue < bestSort))) {
                best = candidate;
                bestSort = sortValue;
            }
        }

        Rule result = best == null ? new Rule(null, new List<Signal_Parameter__mdt>()) : best;
        for (Signal_Parameter__mdt g : globals) {
            if (!result.values.containsKey(g.Parameter_Name__c)) {
                result.values.put(g.Parameter_Name__c, g.Parameter_Value__c);
                result.types.put(g.Parameter_Name__c, g.Data_Type__c);
            }
        }
        return result;
    }

    private static Boolean scopeMatches(
        Signal_Parameter__mdt p,
        Set<String> userGroups,
        String recordType,
        String stage,
        String segment
    ) {
        if (String.isNotBlank(p.Permission_Set_Group__c) && (userGroups == null || !userGroups.contains(p.Permission_Set_Group__c))) {
            return false;
        }
        return blankOrSame(p.Scope_Record_Type__c, recordType) &&
            blankOrSame(p.Scope_Stage__c, stage) &&
            blankOrSame(p.Scope_Segment__c, segment);
    }

    /** The parameters of one rule, with typed getters. */
    public class Rule {
        public String ruleKey;
        public Map<String, String> values = new Map<String, String>();
        public Map<String, String> types = new Map<String, String>();

        public Rule(String ruleKey, List<Signal_Parameter__mdt> rows) {
            this.ruleKey = ruleKey;
            for (Signal_Parameter__mdt p : rows) {
                values.put(p.Parameter_Name__c, p.Parameter_Value__c);
                types.put(p.Parameter_Name__c, p.Data_Type__c);
            }
        }

        public Boolean has(String name) {
            return String.isNotBlank(values.get(name));
        }

        public String getText(String name) {
            String v = values.get(name);
            return v == null ? null : v.trim();
        }

        public Decimal getDecimal(String name) {
            String v = getText(name);
            if (String.isBlank(v)) {
                return null;
            }
            try {
                return Decimal.valueOf(v.removeEnd('%').trim());
            } catch (Exception e) {
                return null;
            }
        }

        public Integer getInteger(String name) {
            Decimal d = getDecimal(name);
            return d == null ? null : d.intValue();
        }

        public Boolean getBoolean(String name) {
            String v = getText(name);
            return v != null && (v.equalsIgnoreCase('true') || v.equalsIgnoreCase('yes') || v == '1');
        }

        /** Values separated by | or new lines, trimmed, blanks removed. */
        public List<String> getList(String name) {
            return splitPipes(values.get(name));
        }
    }

    // ------------------------------------------------------------------ helpers

    public static List<String> splitList(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) {
            return out;
        }
        for (String part : raw.split('[,;\\r\\n]+')) {
            if (String.isNotBlank(part)) {
                out.add(part.trim());
            }
        }
        return out;
    }

    public static List<String> splitPipes(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) {
            return out;
        }
        for (String part : raw.split('[|\\r\\n]+')) {
            if (String.isNotBlank(part)) {
                out.add(part.trim());
            }
        }
        return out;
    }

    private static Boolean sameText(String a, String b) {
        return a != null && b != null && a.equalsIgnoreCase(b);
    }

    private static Boolean blankOrSame(String configured, String actual) {
        return String.isBlank(configured) || (actual != null && configured.trim().equalsIgnoreCase(actual.trim()));
    }
}

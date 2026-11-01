/**
 * Fills {Token} placeholders in prompts, names and descriptions.
 * Unknown tokens are removed rather than shown to the advisor.
 */
public with sharing class SigTokens {
    public static String fill(String template, Map<String, String> tokens) {
        if (String.isBlank(template)) {
            return template;
        }
        Map<String, String> all = tokens == null ? new Map<String, String>() : new Map<String, String>(tokens);
        if (!all.containsKey('MMM YYYY')) {
            all.put('MMM YYYY', monthYear(SigClock.today()));
        }
        if (!all.containsKey('Today')) {
            all.put('Today', formatDate(SigClock.today()));
        }
        String out = template;
        for (String key : all.keySet()) {
            String value = all.get(key);
            out = out.replace('{' + key + '}', value == null ? '' : value);
        }
        out = out.replaceAll('\\{[A-Za-z0-9_ ]+\\}', '');
        return out.normalizeSpace();
    }

    public static String monthYear(Date d) {
        return d == null ? '' : Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('MMM yyyy');
    }

    public static String formatDate(Date d) {
        return d == null ? '' : d.format();
    }
}

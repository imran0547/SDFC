/**
 * Single source of "today" and "now" so tests can pin the date.
 */
public with sharing class SigClock {
    @TestVisible
    static Date todayOverride;
    @TestVisible
    static Datetime nowOverride;

    public static Date today() {
        return todayOverride != null ? todayOverride : Date.today();
    }

    public static Datetime now() {
        return nowOverride != null ? nowOverride : Datetime.now();
    }
}

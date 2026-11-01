/**
 * Business-day arithmetic. Skips Saturdays and Sundays, and also holidays when the org's
 * default Business Hours mark the day as closed.
 */
public with sharing class SigDates {
    @TestVisible
    static Boolean useBusinessHours = true;

    public static Date addBusinessDays(Date start, Integer days) {
        if (start == null) {
            return null;
        }
        Integer remaining = days == null ? 0 : Math.max(days, 0);
        Id hoursId = useBusinessHours ? defaultBusinessHoursId() : null;
        Date d = start;
        Integer guard = 0;
        while (remaining > 0 && guard < 366) {
            d = d.addDays(1);
            guard++;
            if (isBusinessDay(d, hoursId)) {
                remaining--;
            }
        }
        return d;
    }

    public static Boolean isBusinessDay(Date d, Id hoursId) {
        Datetime noon = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0));
        String weekday = noon.format('u'); // 1 = Monday ... 7 = Sunday
        if (weekday == '6' || weekday == '7') {
            return false;
        }
        return hoursId == null || BusinessHours.isWithin(hoursId, noon);
    }

    private static Id defaultBusinessHoursId() {
        List<BusinessHours> rows = [SELECT Id FROM BusinessHours WHERE IsDefault = TRUE AND IsActive = TRUE LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Id;
    }
}

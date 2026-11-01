/**
 * Writes failures and skipped data sources to Signal_Log__c.
 *
 * Runs without sharing so a log can always be written, whatever the user's access.
 * Logging never throws: a failed log write is sent to the debug log instead.
 */
public without sharing class SigLog {
    public static void error(String signalKey, Id recordId, String message, Exception e) {
        String detail = e == null ? null : e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString();
        write('Error', signalKey, recordId, message, detail);
    }

    public static void warn(String signalKey, Id recordId, String message) {
        write('Warning', signalKey, recordId, message, null);
    }

    public static void info(String signalKey, Id recordId, String message) {
        write('Info', signalKey, recordId, message, null);
    }

    private static void write(String level, String signalKey, Id recordId, String message, String detail) {
        try {
            insert new Signal_Log__c(
                Level__c = level,
                Signal_Key__c = signalKey == null ? null : signalKey.left(80),
                Record_Id__c = recordId,
                Message__c = message == null ? null : message.left(32000),
                Detail__c = detail == null ? null : detail.left(32000),
                User_Id__c = UserInfo.getUserId()
            );
        } catch (Exception logFailure) {
            System.debug(LoggingLevel.ERROR, 'SigLog could not write: ' + logFailure.getMessage() + ' / ' + message);
        }
    }
}

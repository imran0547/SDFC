/**
 * What the running user may see: record access, permission set groups and custom permissions.
 */
public with sharing class SigAccess {
    @TestVisible
    static Set<String> groupsOverride;
    @TestVisible
    static Set<String> customPermissionsOverride;

    private static Set<String> groupCache;

    /** Developer names of the permission set groups assigned to the running user. */
    public static Set<String> userGroups() {
        if (groupsOverride != null) {
            return groupsOverride;
        }
        if (groupCache == null) {
            groupCache = new Set<String>();
            try {
                for (PermissionSetAssignment a : [
                    SELECT PermissionSetGroup.DeveloperName
                    FROM PermissionSetAssignment
                    WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetGroupId != NULL
                ]) {
                    if (a.PermissionSetGroup != null) {
                        groupCache.add(a.PermissionSetGroup.DeveloperName);
                    }
                }
            } catch (Exception e) {
                // Some users cannot query assignments; audience rows that use a custom permission still work.
                SigLog.warn(null, null, 'Permission set groups could not be read for the running user.');
            }
        }
        return groupCache;
    }

    public static Boolean hasCustomPermission(String apiName) {
        if (String.isBlank(apiName)) {
            return false;
        }
        if (customPermissionsOverride != null) {
            return customPermissionsOverride.contains(apiName);
        }
        return FeatureManagement.checkPermission(apiName);
    }

    /** True when the running user can read the record. */
    public static Boolean canRead(Id recordId) {
        if (recordId == null) {
            return false;
        }
        List<UserRecordAccess> rows = [
            SELECT RecordId, HasReadAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
        ];
        return !rows.isEmpty() && rows[0].HasReadAccess;
    }
}

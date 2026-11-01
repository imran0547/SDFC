"""Declarative mapping templates (the 'template-driven transformation' layer).

Each source org gets a template that maps its fields to the canonical target
schema, names the date format, and points at versioned picklist maps. Adding a
third org means adding a template, not writing new code.
"""
TEMPLATE_VERSION = "1.0.0"

PICKLIST_MAPS = {
    "B.Industry": {
        "Tech": "Technology", "Hi-Tech": "Technology",
        "Financial Services": "Finance", "Banking": "Finance",
        "Health Care": "Healthcare", "Mfg": "Manufacturing", "Retail": "Retail",
        "Oil & Gas": "Energy", "Utilities": "Energy", "Education": "Education",
        "Misc": "Other",
    },
    "B.Stage": {
        "Stage 1": "Prospecting", "Stage 2": "Qualification", "Stage 3": "Proposal",
        "Stage 4": "Negotiation", "Won": "Closed Won", "Lost": "Closed Lost",
    },
}
IDENTITY = None  # marker: values already canonical

TEMPLATES = {
    "A": {
        "datetime_format": "iso_utc",
        "date_format": "%Y-%m-%d",
        "Account": {"fields": {"Name": "Name", "City": "BillingCity", "State": "BillingState",
                               "Phone": "Phone", "Website": "Website", "Industry": "Industry",
                               "AnnualRevenue": "AnnualRevenue", "CreatedDate": "CreatedDate",
                               "LastModifiedDate": "LastModifiedDate"},
                    "picklists": {"Industry": IDENTITY}},
        "Contact": {"fields": {"FirstName": "FirstName", "LastName": "LastName", "Email": "Email",
                               "Phone": "Phone", "Title": "Title", "AccountId": "AccountId",
                               "CreatedDate": "CreatedDate", "LastModifiedDate": "LastModifiedDate"},
                    "picklists": {}},
        "Opportunity": {"fields": {"Name": "Name", "Amount": "Amount", "StageName": "StageName",
                                   "CloseDate": "CloseDate", "AccountId": "AccountId",
                                   "CreatedDate": "CreatedDate", "LastModifiedDate": "LastModifiedDate"},
                        "picklists": {"StageName": IDENTITY}},
    },
    "B": {
        "datetime_format": "%m/%d/%Y %I:%M %p",
        "timezone": "America/Chicago",
        "date_format": "%m/%d/%Y",
        "Account": {"fields": {"Name": "Company_Name__c", "City": "City__c", "State": "State__c",
                               "Phone": "Phone_Number__c", "Website": "Web__c", "Industry": "Sector__c",
                               "AnnualRevenue": "Revenue_USD__c", "CreatedDate": "Created__c",
                               "LastModifiedDate": "Modified__c"},
                    "picklists": {"Industry": "B.Industry"}},
        "Contact": {"fields": {"FirstName": "First__c", "LastName": "Last__c", "Email": "Email__c",
                               "Phone": "Mobile__c", "Title": "Job_Title__c", "AccountId": "Company__c",
                               "CreatedDate": "Created__c", "LastModifiedDate": "Modified__c"},
                    "picklists": {}},
        "Opportunity": {"fields": {"Name": "Deal_Name__c", "Amount": "Value__c", "StageName": "Phase__c",
                                   "CloseDate": "Expected_Close__c", "AccountId": "Customer__c",
                                   "CreatedDate": "Created__c", "LastModifiedDate": "Modified__c"},
                        "picklists": {"StageName": "B.Stage"}},
    },
}

# Survivorship: source priority used to break ties (acquirer first).
SOURCE_PRIORITY = {"A": 0, "B": 1}

# Matching configuration (logged with every run for governance).
MATCH_CONFIG = {
    "Account": {"weights": {"name": 0.55, "city": 0.15, "phone": 0.15, "domain": 0.15},
                "threshold": 0.85},
    "Contact": {"weights": {"first": 0.20, "last": 0.35, "email": 0.25, "phone": 0.20},
                "threshold": 0.85},
}

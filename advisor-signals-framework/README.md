# Advisor Signals Framework

A reusable Salesforce framework for **human-in-the-loop signal detection**: it notices
that something has changed for a client or a deal (a stalled Opportunity, a job change,
a life event mentioned in a note) and shows the user a card with a pre-filled next step.
The user decides; nothing is saved or sent without their confirmation.

It runs the same way on Account and Opportunity record pages and, optionally, in an
Agentforce employee agent. It is company-neutral: everything firm-specific (thresholds,
wording, stages, record types, audiences) is configuration, and new signals plug in as
one Apex class each.

## Design principles

| Principle | How the framework applies it |
| --- | --- |
| Tiered evidence | Each source decides what is strong enough; weak evidence never raises a card on its own (see `SigNoteSignalSource`: one strong note, or two weak notes = Inferred). |
| Evidence and confidence | Every card cites its source and date and carries a confidence label (Confirmed / Inferred / Unconfirmed) that your wording can follow. |
| Configuration over code | Windows, thresholds, wording, defaults and audiences live in custom metadata. |
| Compute, don't store | Signals are worked out live each time. Only the user's response is stored, in `Signal_Response__c`, one row per user per signal instance. |
| User in control, honest fallback | Every write opens a pre-filled form the user saves, the signal is rechecked just before saving, and failures say what did and did not change, are logged, and keep the card open. |

## How it works

```
record page / agent panel
        │  getInsights / Show Signals
        ▼
SigEngine ── for each active Signal_Definition__mdt on this object
   │  1. user can read the record          (SigAccess)
   │  2. audience allows the user          (Signal_Audience__mdt)
   │  3. client record type included       (Included_Record_Types__c)
   │  4. source.evaluate(ctx)              (your SigSource class)
   │  5. one insight per group, newest wins
   │  6. Draft Opportunity → skip if an open Opportunity exists (SigGuards)
   │  7. wording, defaults, response key   (from the definition)
   ▼
SigResponseService ── hide or annotate using the user's earlier responses
        ▼
sigInsightList → sigInsightCard → sigRecordFormModal (user saves) → Acted On
```

## What is included

| Area | Components |
| --- | --- |
| Engine | `SigEngine`, `SigSource` (interface), `SigContext`, `SigInsight`, `SigConfig` (+ `SigConfig.Rule`), `SigAccess`, `SigRecordInfo`, `SigGuards`, `SigResponseService`, `SigOpportunityDefaults`, `SigFollowUpService`, `SigTokens`, `SigDates`, `SigClock`, `SigLog`, `SigException` |
| Notes ("rules first, AI second") | `SigNote`, `SigNoteVerdict`, `SigNoteProvider` (interface), `SigNoteClassifier` (interface), `SigActivityNoteProvider`, `SigKeywordNoteClassifier` |
| Sample signals | `SigStalledOpportunitySource` (Next Best Action), `SigFieldChangeSource` (Insight), `SigNoteSignalSource` (Insight) |
| Endpoints | `SigCardController` (components), `SigAgentAction` ("Show Signals"), `SigRecordResponseAction` ("Record Signal Not Now") |
| UI | `sigInsightList` (record page), `sigInsightCard`, `sigRecordFormModal` |
| Agent renderer (optional, `agent-app/`) | `sigAgentCards` LWC and the `sigSignalCards` Lightning Type |
| Data | `Signal_Response__c` (private sharing), `Signal_Log__c` |
| Configuration | `Signal_Definition__mdt`, `Signal_Parameter__mdt`, `Signal_Audience__mdt`, plus sample rows |
| Access | Permission sets `Signal_Framework_User` and `Signal_Framework_Admin` |
| Tests | `SigEngineTest`, `SigConfigTest`, `SigFieldChangeSourceTest`, `SigNoteSignalSourceTest`, `SigCardControllerTest`, `SigUtilitiesTest`, helper `SigTestData` |

## Install

Requires the Salesforce CLI and an org on API 62.0 or later.

```bash
sf org login web --alias target
sf project deploy start --source-dir force-app --target-org target --test-level RunSpecifiedTests \
  --tests SigEngineTest SigConfigTest SigFieldChangeSourceTest SigNoteSignalSourceTest SigCardControllerTest SigUtilitiesTest
sf org assign permset --name Signal_Framework_User --target-org target
```

Then add **Signal Cards** (`sigInsightList`) to the Opportunity record page in Lightning App
Builder. Only the `STALLED_OPPORTUNITY` sample is active, and its stages are the standard
sample stages: change them to yours (see below).

The agent renderer is a separate package directory so the core deploys on its own. Deploy it
after you set up the agent: `sf project deploy start --source-dir agent-app --target-org target`.

## Configure a signal

**Signal_Definition__mdt**: one row per signal.

| Field | Purpose |
| --- | --- |
| Signal Key | Unique key; joins parameters and audiences |
| Agent | Insight or Next Best Action (lets two agents or two lists share the engine) |
| Anchor Object | Account or Opportunity |
| Source Class | Apex class implementing `SigSource` |
| Prompt Template | Card sentence with tokens such as `{ClientName}`, `{Date}`, `{Source}`, `{Confidence}`, `{OpportunityName}`, `{MMM YYYY}`, plus any token your source sets |
| Primary Action, labels | Draft Opportunity, Update Opportunity or Create Task; button labels |
| Resurface Days, Show On Ask | Not now behavior: 0 = hidden for the rest of the browser session; > 0 = hidden that many days. Show On Ask lets an explicit request still show it, with a "You skipped this on…" line |
| Included Record Types | Client record types in scope; blank = all |
| Lookback Days | Evidence window |
| Rule Sort Parameter | When several parameter rules match, the smallest value of this parameter wins (for example `Threshold_Days`) |
| Opportunity Record Type / Stage / Name Pattern / Close Date Offset | Draft Opportunity defaults. A closed or unknown stage is never suggested |
| Allow Task, Task Priority, Task Due Business Days | Follow-up Task offered after the primary action |

**Signal_Parameter__mdt**: named, typed values a source reads through `ctx.rule(...)`.
Rows with the same Rule Key form one rule; blank scope fields (record type, stage, segment,
permission set group) match everything; rows with no Rule Key apply to every rule.

**Signal_Audience__mdt**: who may see a signal, by permission set group or custom permission.
A signal with no active audience rows is shown to everyone with `Signal_Framework_User`.

## Add a signal

1. Write a class that implements `SigSource`:

```apex
public with sharing class LargeDepositSource implements SigSource {
    public List<SigInsight> evaluate(SigContext ctx) {
        List<SigInsight> out = new List<SigInsight>();
        SigConfig.Rule rule = ctx.rule(null, null, null);
        Decimal minimum = rule.getDecimal('Minimum_Amount');
        // Read your data as the user (WITH USER_MODE), inside ctx.lookbackStart().
        // For each qualifying event:
        SigInsight ins = ctx.newInsight();
        ins.changeType = 'Large Deposit';
        ins.evidenceId = '<record id>';         // new evidence = new response key = fresh card
        ins.evidenceDate = Date.today();
        ins.source = 'Money movement';
        ins.confidence = 'Inferred';            // wording should follow the label
        ins.tokens.put('Amount', '<formatted amount>');
        out.add(ins);
        return out;
    }
}
```

2. Add a `Signal_Definition__mdt` row naming the class, plus parameter rows.
3. Add tests (see `SigTestData` for building metadata rows in memory).

You do not need a new object, a new component or a new agent.

## Read notes with an LLM (optional)

`SigNoteSignalSource` reads recent notes, keeps at most three that mention the signal
(keyword gate), and asks a classifier about only those. The default classifier uses phrase
lists. To use a Prompt Builder template instead, implement `SigNoteClassifier` and name the
class in the `Note_Classifier_Class` parameter. The engine still makes the final decision,
and a classifier failure is logged and raises nothing.

Example to adapt (check the ConnectApi signatures against your org's API version):

```apex
public with sharing class PromptTemplateNoteClassifier implements SigNoteClassifier {
    public List<SigNoteVerdict> classify(List<SigNote> notes, SigConfig.Rule rule) {
        List<SigNoteVerdict> out = new List<SigNoteVerdict>();
        for (SigNote n : notes) {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            ConnectApi.WrappedValue note = new ConnectApi.WrappedValue();
            note.value = n.text; // passed as data, never as instructions
            input.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Note' => note };
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptBuilderPreview';
            input.isPreview = false;
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation res =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(rule.getText('Prompt_Template_Name'), input);
            // Ask the template to answer as JSON: {"strength":"Strong|Weak|Excluded|None","quote":"...","confidence":"..."}
            Map<String, Object> verdict = (Map<String, Object>) JSON.deserializeUntyped(res.generations[0].text);
            SigNoteVerdict v = new SigNoteVerdict(n, (String) verdict.get('strength'), (String) verdict.get('quote'));
            v.confidence = (String) verdict.get('confidence');
            out.add(v);
        }
        return out;
    }
}
```

Use your own note store by implementing `SigNoteProvider` (for example meeting-note or
interaction-summary objects) and naming it in `Note_Provider_Class`. The default reads Task
and Event descriptions.

## Agent setup (optional)

1. In Agentforce Builder, add the invocable actions **Show Signals** (`SigAgentAction`) and
   **Record Signal Not Now** (`SigRecordResponseAction`) to your employee agent's subagent.
   Pass the record Id from the conversation context; pass Agent = Insight or Next Best
   Action if you run separate agents.
2. Deploy `agent-app/`. It maps the Show Signals output to the `sigSignalCards` Lightning
   Type, which renders `sigAgentCards`, the same list and card as the record page. Verify the
   Lightning Type file format and the `lightning__AgentforceOutput` target against the
   current Salesforce documentation for your release before deploying.
3. The action also returns a plain-text `Summary` for channels that cannot show cards.

## Security model

- All reads and writes run as the user (`with sharing`, `USER_MODE`), so sharing, field
  access, validation rules and triggers apply.
- One deliberate exception: `SigGuards.hasOpenOpportunity` counts open Opportunities without
  sharing, so an Opportunity the user cannot see still prevents a duplicate. It returns only
  yes or no.
- `SigLog` writes logs without sharing so failures are always recorded.
- A user can record a response only against their own response key.
- `Signal_Response__c` uses private sharing: each user sees only their own responses, and one
  user's Not now never hides a card from someone else.

## Known limits and things to verify in your org

- This project has been syntax-checked but not yet deployed to an org: run the deploy and
  tests in a sandbox first.
- Sample rows use standard sample stage names (`Prospecting`, `Proposal/Price Quote`,
  `Negotiation/Review`); replace them with yours. The `Employer_Change` sample expects an
  `Employer__c` field with field history tracking; it is inactive until you configure it.
- Days in stage uses `Opportunity.LastStageChangeInDays` and falls back to the stage-change
  or created date.
- UI text is in English in the components; move it to custom labels to translate.
- Session-only Not now uses a browser-session token; a new tab or login starts a new session.
- Email follow-ups are not included; add them as another action in `sigInsightList` if needed.

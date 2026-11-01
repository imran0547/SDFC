# Agentforce setup

The framework is designed for two Agentforce employee agents that share one engine, one
response object and one set of actions, the way most advisor teams run them:

- **New Opportunity Insights** – life events and changing circumstances (signals with
  Agent = `Insight`).
- **Next Best Action** – timely actions on existing relationships, such as a stalled
  Opportunity (signals with Agent = `Next Best Action`).

Both follow the same structure in Agentforce Builder:

```
<Agent>                          AI Agent
└── Agent Router                 start subagent: greet the user, route to a subagent
    ├── <Signals subagent>       New Opportunity Insights  |  Next Best Actions
    ├── Ambiguous Question       ask a clarifying question
    └── Off Topic                redirect to what the agent can do
```

The agent never saves anything itself. Its cards open pre-filled forms, and the user saves.

## Actions

All actions are invocable Apex in `force-app`. Add them to the signals subagent in
Agentforce Builder (New Action → Apex). Every action that takes an **Agent** input should
be given `Insight` in the New Opportunity Insights agent and `Next Best Action` in the
Next Best Action agent.

| Builder action name (suggested) | Apex class | Agent | Purpose | Output rendering |
| --- | --- | --- | --- | --- |
| Identify Record by Name | `SigFindRecordAction` | both | Find the client or Opportunity the user named; ask which one if several match | text |
| Get Signals | `SigGetSignalsAction` | both | Signals as text for reasoning, with response keys | text |
| Show Signals | `SigAgentAction` | both | Signals as cards (`sigSignalCards` Lightning Type) | cards |
| Show Past Signal Responses | `SigPastResponsesAction` | Insights | The user's earlier Not Now / Acted On responses for the record | text |
| Get Follow-ups | `SigGetFollowUpsAction` | Insights | Which follow-ups a signal allows | text |
| Create Follow-up | `SigCreateFollowUpAction` | Insights | A pre-filled Task for the user to review and save (`sigFollowUpDraft` Lightning Type) | card |
| Record Signal Response | `SigRecordResponseAction` | both | Save "Not now" when the user declines in conversation | text |

A minimal Next Best Action agent needs only **Show Signals** and **Identify Record by Name**.
The New Opportunity Insights agent typically uses all seven.

On the outputs of Show Signals and Create Follow-up, choose the Lightning Types
`sigSignalCards` and `sigFollowUpDraft` so the agent panel shows the same cards as the record
page. Deploy `agent-app/` first (see README).

## Inputs from context

Map the **Record Id** input to the record the user is looking at (the agent's record-context
variable, for example `currentRecordId`), and fall back to the Id returned by Identify Record
by Name when the user names a client.

## Suggested instructions

Adjust the wording to your firm. These are written for the New Opportunity Insights subagent;
for Next Best Actions, replace "insights" with "next best actions" and drop the follow-up steps
that do not apply.

**Subagent description**

> Shows New Opportunity Insights for the client on screen or a client the user names, and
> helps the user act on them: draft an Opportunity, create a follow-up Task, or skip for now.

**Subagent instructions**

1. If the user names a client, run *Identify Record by Name*. If several records match, list
   them and ask which one. If none match, say so.
2. To show insights, run *Show Signals* with the record Id and Agent = `Insight`. Always show
   every insight returned, including skipped ones; their reminder says when they were skipped.
3. Use *Get Signals* when you need the details (response key, evidence, confidence) to answer
   a question about an insight. Quote the evidence and its date; describe intent as inferred
   when the confidence is not Confirmed.
4. Never create, update or send anything yourself. The card buttons open pre-filled forms that
   the user saves.
5. If the user says "not now" or "skip" for an insight, run *Record Signal Response* with that
   insight's response key.
6. After the user has saved an Opportunity, run *Get Follow-ups*. If a Task is allowed, offer
   it and run *Create Follow-up* when the user agrees.
7. If the user asks what they did before, run *Show Past Signal Responses*.
8. If an action fails, say plainly what did and did not happen and suggest trying again or doing
   it manually. Never say an action succeeded unless its output says so.
9. Only discuss this agent's signals. For a question that belongs to the other agent (for
   example, stalled Opportunities in the insights agent), tell the user to switch to that agent.

**Off Topic** and **Ambiguous Question** can keep Agentforce's standard instructions: redirect
to what the agent can do, or ask one clarifying question.

## Checklist

- [ ] `force-app` deployed and tests passing
- [ ] `Signal_Framework_User` assigned to the agent's users
- [ ] Signal definitions active for the right Agent value, with your stages and thresholds
- [ ] `agent-app` deployed (Lightning Types and renderers)
- [ ] Actions added to the signals subagent, Agent input set, record Id mapped
- [ ] Show Signals and Create Follow-up outputs mapped to their Lightning Types
- [ ] Tested in the agent preview on an Opportunity and on a client record

The Agentforce metadata formats (agent definitions, Lightning Types, the
`lightning__AgentforceOutput` target) change between releases; check them against the current
Salesforce documentation and deploy to a sandbox first.

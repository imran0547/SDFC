"""Step 1: load BPIC 2012, keep COMPLETE events, map to CRM-style labels,
derive outcome, deal-value segment, and a temporal train/test split."""
import warnings, pickle
warnings.filterwarnings("ignore")
import pandas as pd
import pm4py

LABELS = {
    "A_SUBMITTED": "Lead Submitted",
    "A_PARTLYSUBMITTED": "Lead Registered in CRM",
    "A_PREACCEPTED": "Lead Pre-qualified",
    "A_ACCEPTED": "Lead Qualified",
    "A_FINALIZED": "Opportunity Finalized",
    "A_DECLINED": "Lead Declined",
    "A_CANCELLED": "Opportunity Cancelled",
    "A_REGISTERED": "Deal Registered",
    "A_APPROVED": "Deal Approved",
    "A_ACTIVATED": "Deal Won",
    "O_SELECTED": "Offer Selected",
    "O_CREATED": "Proposal Created",
    "O_SENT": "Proposal Sent",
    "O_SENT_BACK": "Proposal Returned",
    "O_ACCEPTED": "Proposal Accepted",
    "O_DECLINED": "Proposal Declined",
    "O_CANCELLED": "Proposal Cancelled",
    "W_Afhandelen leads": "Handle Lead",
    "W_Completeren aanvraag": "Complete Lead Data",
    "W_Nabellen offertes": "Follow-up Call (Proposal)",
    "W_Valideren aanvraag": "Validate Opportunity",
    "W_Nabellen incomplete dossiers": "Follow-up Call (Missing Info)",
    "W_Beoordelen fraude": "Fraud Review",
    "W_Wijzigen contractgegevens": "Change Contract Details",
}

def load(path="/tmp/data/bpic2012.xes.gz"):
    df = pm4py.read_xes(path)
    raw_events = len(df)
    df = df[df["lifecycle:transition"] == "COMPLETE"].copy()
    df["orig"] = df["concept:name"]
    df["concept:name"] = df["orig"].map(LABELS)
    assert df["concept:name"].notna().all()
    df = df.sort_values(["case:concept:name", "time:timestamp"]).reset_index(drop=True)
    df["case:AMOUNT_REQ"] = pd.to_numeric(df["case:AMOUNT_REQ"], errors="coerce")

    g = df.groupby("case:concept:name")
    acts = g["concept:name"].apply(set)
    cases = pd.DataFrame({
        "start": g["time:timestamp"].min(),
        "end": g["time:timestamp"].max(),
        "amount": g["case:AMOUNT_REQ"].first(),
        "n_events": g.size(),
    })
    def outcome(s):
        if "Deal Won" in s: return "won"
        if "Lead Declined" in s: return "declined"
        if "Opportunity Cancelled" in s: return "cancelled"
        return "open"
    cases["outcome"] = acts.map(outcome)
    return df, cases, raw_events

if __name__ == "__main__":
    df, cases, raw = load()
    print("raw events", raw, "complete events", len(df), "cases", len(cases))
    print(cases["outcome"].value_counts())
    closed = cases[cases["outcome"] != "open"].sort_values("start")
    n_train = int(len(closed) * 0.7)
    train_ids = set(closed.index[:n_train]); test_ids = set(closed.index[n_train:])
    print("closed", len(closed), "train", len(train_ids), "test", len(test_ids))
    print("split date", closed["start"].iloc[n_train])
    pickle.dump(dict(df=df, cases=cases, train=train_ids, test=test_ids, raw=raw),
                open("/tmp/work/prep.pkl", "wb"))

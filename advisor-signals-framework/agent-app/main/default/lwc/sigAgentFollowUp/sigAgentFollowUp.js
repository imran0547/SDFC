import { LightningElement, api } from 'lwc';
import SigRecordFormModal from 'c/sigRecordFormModal';

/**
 * Agent-panel renderer for the "Create Follow-up" action (Lightning Type sigFollowUpDraft).
 * Shows the drafted Task and opens it in a pre-filled form; the advisor saves it.
 */
export default class SigAgentFollowUp extends LightningElement {
    /** The SigCreateFollowUpAction.Response object: { draftJson, summary, message }. */
    @api value;
    status;

    get draft() {
        try {
            return this.value && this.value.draftJson ? JSON.parse(this.value.draftJson) : null;
        } catch (e) {
            return null;
        }
    }

    get hasDraft() {
        return !!this.draft && !this.status;
    }

    get message() {
        return this.value && this.value.message;
    }

    get summary() {
        return this.value && this.value.summary;
    }

    async handleOpen() {
        const draft = this.draft;
        const result = await SigRecordFormModal.open({
            size: 'medium',
            label: draft.heading,
            heading: draft.heading,
            objectApiName: draft.objectApiName,
            fields: draft.fields
        });
        if (result && result.status === 'saved') {
            this.status = 'Done – the Task is created.';
        } else if (result && result.status === 'manual') {
            this.status = 'Create the Task from the client or Opportunity record.';
        }
    }
}

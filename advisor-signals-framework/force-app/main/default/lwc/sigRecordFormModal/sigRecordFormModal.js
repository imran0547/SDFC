import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import recheck from '@salesforce/apex/SigCardController.recheck';

/**
 * A pre-filled, editable record form in a modal. Saves through lightning-record-edit-form,
 * as the user, so the org's validation rules, defaults and triggers apply.
 *
 * Before saving it rechecks that the signal still applies (when recheckRecordId and
 * recheckKey are set). Closes with { status: 'saved', id }, { status: 'cancel' },
 * { status: 'manual' } or { status: 'stale', message }.
 */
export default class SigRecordFormModal extends LightningModal {
    @api heading = 'Review and save';
    @api objectApiName;
    @api recordId;
    @api recordTypeId;
    /** [{ fieldName, value }] in display order. */
    @api fields = [];
    @api notice;
    @api recheckRecordId;
    @api recheckKey;

    saving = false;
    errorMessage;

    get fieldList() {
        return (this.fields || []).map((f) => ({ ...f, key: f.fieldName }));
    }

    get saveDisabled() {
        return this.saving;
    }

    handleCancel() {
        this.close({ status: 'cancel' });
    }

    handleManual() {
        this.close({ status: 'manual' });
    }

    async handleSave() {
        this.errorMessage = undefined;
        const inputs = [...this.template.querySelectorAll('lightning-input-field')];
        const valid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        if (!valid) {
            return;
        }
        this.saving = true;
        try {
            if (this.recheckRecordId && this.recheckKey) {
                const stillApplies = await recheck({ recordId: this.recheckRecordId, responseKey: this.recheckKey });
                if (!stillApplies) {
                    this.close({
                        status: 'stale',
                        message: 'This signal no longer applies (for example, the record changed or a covering Opportunity now exists). Nothing was saved.'
                    });
                    return;
                }
            }
            this.template.querySelector('lightning-record-edit-form').submit();
        } catch (e) {
            this.saving = false;
            this.errorMessage = (e && e.body && e.body.message) || 'I can\'t complete that right now, and nothing has been saved.';
        }
    }

    handleSuccess(event) {
        this.saving = false;
        this.close({ status: 'saved', id: event.detail.id });
    }

    handleError(event) {
        this.saving = false;
        const detail = event && event.detail;
        const message = detail && (detail.detail || detail.message);
        this.errorMessage = 'I couldn\'t save this, and nothing has been changed.' + (message ? ' ' + message : '') +
            ' You can try again or create it manually.';
    }
}

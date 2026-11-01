import { LightningElement, api } from 'lwc';

/**
 * One signal: the sentence, its evidence, any reminder, and two buttons.
 * After the primary action succeeds it shows the follow-up step instead.
 * Purely presentational: it raises events and never calls Apex.
 *
 * Events: primary, secondary, createtask, done, retry (detail: { responseKey })
 */
export default class SigInsightCard extends LightningElement {
    @api insight;
    /** 'idle' | 'busy' | 'followup' | 'done' */
    @api state = 'idle';
    @api message;
    @api errorMessage;

    get hasEvidence() {
        return this.insight && (this.insight.source || this.insight.evidenceDate || this.insight.evidenceSummary);
    }

    get evidenceLine() {
        const parts = [];
        if (this.insight.source) {
            parts.push(this.insight.source);
        }
        if (this.insight.evidenceDate) {
            parts.push(this.insight.evidenceDate);
        }
        return parts.join(' · ');
    }

    get hasConfidence() {
        return this.insight && this.insight.confidence;
    }

    get confidenceClass() {
        return this.insight.confidence === 'Confirmed'
            ? 'slds-badge slds-theme_success'
            : 'slds-badge slds-badge_lightest';
    }

    get isHigh() {
        return this.insight && this.insight.priority === 'High';
    }

    get notSuggestedText() {
        const list = (this.insight && this.insight.notSuggested) || [];
        return list.length ? 'Not suggested, please fill in: ' + list.join(', ') + '.' : null;
    }

    get isIdle() {
        return this.state === 'idle' || this.state === 'busy';
    }

    get isBusy() {
        return this.state === 'busy';
    }

    get isFollowUp() {
        return this.state === 'followup';
    }

    get isDone() {
        return this.state === 'done';
    }

    get showTask() {
        return this.insight && this.insight.allowTask;
    }

    fire(name) {
        this.dispatchEvent(new CustomEvent(name, { detail: { responseKey: this.insight.responseKey } }));
    }

    handlePrimary() {
        this.fire('primary');
    }

    handleSecondary() {
        this.fire('secondary');
    }

    handleTask() {
        this.fire('createtask');
    }

    handleDone() {
        this.fire('done');
    }

    handleRetry() {
        this.fire('retry');
    }
}

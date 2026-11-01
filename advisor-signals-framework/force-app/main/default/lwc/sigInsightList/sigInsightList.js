import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getInsights from '@salesforce/apex/SigCardController.getInsights';
import recordResponse from '@salesforce/apex/SigCardController.recordResponse';
import getTaskDefaults from '@salesforce/apex/SigCardController.getTaskDefaults';
import logClientError from '@salesforce/apex/SigCardController.logClientError';
import SigRecordFormModal from 'c/sigRecordFormModal';

const SESSION_KEY = 'sigSessionToken';
const OPPORTUNITY_DRAFT_FIELDS = ['Name', 'AccountId', 'StageName', 'CloseDate', 'Amount', 'NextStep', 'Description'];
const OPPORTUNITY_UPDATE_FIELDS = ['StageName', 'CloseDate', 'NextStep'];
const TASK_FIELDS = ['Subject', 'ActivityDate', 'Priority', 'WhoId', 'WhatId', 'OwnerId', 'Description'];
const NOT_SENT = ['RecordTypeId'];

/**
 * The signal list for a record. Used on Account and Opportunity record pages, and in the
 * agent panel through a Lightning Type (sigAgentCards passes the agent's cards in `cards`).
 * Every write opens a pre-filled form that the advisor saves; nothing is saved silently.
 */
export default class SigInsightList extends NavigationMixin(LightningElement) {
    @api recordId;
    /** Insight, Next Best Action, or blank for both (set in App Builder). */
    @api agent;
    @api cardTitle = 'Signals';
    /** Cards supplied by the agent (array of insights). When set, the list does not load itself. */
    @api
    get cards() {
        return this._cards;
    }
    set cards(value) {
        this._cards = value;
        if (Array.isArray(value)) {
            this.insights = value;
            this.loading = false;
        }
    }

    _cards;
    @track insights = [];
    @track cardState = {};
    loading = true;
    loadError;
    sessionToken;

    get surface() {
        return Array.isArray(this._cards) ? 'Agent' : 'Record Page';
    }

    get items() {
        return (this.insights || []).map((insight) => {
            const s = this.cardState[insight.responseKey] || {};
            return {
                key: insight.responseKey,
                insight,
                state: s.state || 'idle',
                message: s.message,
                error: s.error
            };
        });
    }

    get hasItems() {
        return !this.loading && !this.loadError && this.items.length > 0;
    }

    get isEmpty() {
        return !this.loading && !this.loadError && this.items.length === 0;
    }

    connectedCallback() {
        this.sessionToken = this.readSessionToken();
        if (!Array.isArray(this._cards)) {
            this.load(false);
        }
    }

    readSessionToken() {
        try {
            let token = window.sessionStorage.getItem(SESSION_KEY);
            if (!token) {
                token = Date.now().toString(36) + Math.random().toString(36).slice(2, 12);
                window.sessionStorage.setItem(SESSION_KEY, token);
            }
            return token;
        } catch (e) {
            return null;
        }
    }

    async load(explicitAsk) {
        if (!this.recordId) {
            this.loading = false;
            return;
        }
        this.loading = true;
        this.loadError = undefined;
        try {
            this.insights = await getInsights({
                recordId: this.recordId,
                agent: this.agent,
                surface: this.surface,
                explicitAsk: explicitAsk === true,
                sessionToken: this.sessionToken
            });
        } catch (e) {
            this.loadError = this.messageOf(e, 'I can\'t check this record right now. Please try again shortly.');
        } finally {
            this.loading = false;
        }
    }

    handleRefresh() {
        this.load(true);
    }

    // ------------------------------------------------------------------ card events

    find(responseKey) {
        return (this.insights || []).find((i) => i.responseKey === responseKey);
    }

    setState(responseKey, patch) {
        const current = this.cardState[responseKey] || {};
        this.cardState = { ...this.cardState, [responseKey]: { ...current, ...patch } };
    }

    async handleSecondary(event) {
        const insight = this.find(event.detail.responseKey);
        if (!insight) {
            return;
        }
        this.setState(insight.responseKey, { state: 'busy', error: undefined });
        try {
            await this.respond(insight, 'Not Now', null);
            this.insights = this.insights.filter((i) => i.responseKey !== insight.responseKey);
        } catch (e) {
            this.setState(insight.responseKey, { state: 'idle', error: this.messageOf(e, 'I couldn\'t save that. Nothing was changed.') });
        }
    }

    async handlePrimary(event) {
        const insight = this.find(event.detail.responseKey);
        if (!insight) {
            return;
        }
        this.setState(insight.responseKey, { error: undefined });
        if (insight.primaryAction === 'Create Task') {
            await this.openTask(insight, insight.opportunityId || insight.clientId, true);
            return;
        }
        const isUpdate = insight.primaryAction === 'Update Opportunity';
        const values = insight.suggestedValues || {};
        const result = await SigRecordFormModal.open({
            size: 'medium',
            label: insight.primaryLabel,
            heading: insight.primaryLabel,
            objectApiName: 'Opportunity',
            recordId: isUpdate ? insight.opportunityId : undefined,
            recordTypeId: isUpdate ? undefined : values.RecordTypeId,
            fields: this.fieldList(isUpdate ? OPPORTUNITY_UPDATE_FIELDS : OPPORTUNITY_DRAFT_FIELDS, values),
            notice: this.notSuggestedNotice(insight),
            recheckRecordId: insight.anchorId,
            recheckKey: insight.responseKey
        });
        await this.afterPrimary(insight, result, isUpdate);
    }

    async afterPrimary(insight, result, isUpdate) {
        if (!result || result.status === 'cancel') {
            return;
        }
        if (result.status === 'stale') {
            this.setState(insight.responseKey, { state: 'done', message: result.message });
            return;
        }
        if (result.status === 'manual') {
            this.navigateManual(insight, isUpdate);
            return;
        }
        if (result.status === 'saved') {
            const savedId = result.id || insight.opportunityId;
            try {
                await this.respond(insight, 'Acted On', savedId);
            } catch (e) {
                logClientError({ signalKey: insight.signalKey, recordId: savedId, message: 'Acted On could not be recorded: ' + this.messageOf(e, '') });
            }
            const name = (insight.suggestedValues && insight.suggestedValues.Name) || 'The Opportunity';
            const message = isUpdate ? 'Done – the Opportunity is updated.' : 'Done – ' + name + ' is created.';
            this.setState(insight.responseKey, {
                state: insight.allowTask ? 'followup' : 'done',
                message: insight.allowTask ? message + ' Would you like a follow-up Task?' : message,
                savedId
            });
        }
    }

    async handleCreateTask(event) {
        const insight = this.find(event.detail.responseKey);
        const s = this.cardState[event.detail.responseKey] || {};
        if (insight) {
            await this.openTask(insight, s.savedId || insight.opportunityId || insight.clientId, false);
        }
    }

    handleDone(event) {
        const s = this.cardState[event.detail.responseKey] || {};
        this.setState(event.detail.responseKey, {
            state: 'done',
            message: s.taskCreated ? 'Done – the Opportunity and the follow-up Task are saved.' : 'Done.'
        });
    }

    async openTask(insight, whatId, isPrimary) {
        let defaults = {};
        try {
            defaults = await getTaskDefaults({ insightJson: JSON.stringify(insight), whatId });
        } catch (e) {
            this.setState(insight.responseKey, { error: this.messageOf(e, 'I can\'t prepare the Task right now. You can create it manually.') });
            return;
        }
        const result = await SigRecordFormModal.open({
            size: 'medium',
            label: 'Create a Task',
            heading: 'Create a Task',
            objectApiName: 'Task',
            fields: this.fieldList(TASK_FIELDS, defaults),
            recheckRecordId: isPrimary ? insight.anchorId : undefined,
            recheckKey: isPrimary ? insight.responseKey : undefined
        });
        if (!result || result.status === 'cancel') {
            return;
        }
        if (result.status === 'stale') {
            this.setState(insight.responseKey, { state: 'done', message: result.message });
            return;
        }
        if (result.status === 'manual') {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Task', actionName: 'new' },
                state: { defaultFieldValues: encodeDefaultFieldValues(this.plain(defaults)) }
            });
            return;
        }
        if (result.status === 'saved') {
            if (isPrimary) {
                try {
                    await this.respond(insight, 'Acted On', result.id);
                } catch (e) {
                    logClientError({ signalKey: insight.signalKey, recordId: result.id, message: 'Acted On could not be recorded: ' + this.messageOf(e, '') });
                }
                this.setState(insight.responseKey, { state: 'done', message: 'Done – the Task is created.' });
            } else {
                this.setState(insight.responseKey, { taskCreated: true, state: 'done', message: 'Done – the Opportunity and the follow-up Task are saved.' });
            }
        }
    }

    // ------------------------------------------------------------------ helpers

    respond(insight, status, createdRecordId) {
        return recordResponse({
            insightJson: JSON.stringify(insight),
            status,
            surface: this.surface,
            sessionToken: this.sessionToken,
            createdRecordId
        });
    }

    fieldList(preferred, values) {
        const list = [];
        const seen = new Set();
        preferred.forEach((name) => {
            list.push({ fieldName: name, value: values[name] });
            seen.add(name);
        });
        Object.keys(values || {}).forEach((name) => {
            if (!seen.has(name) && !NOT_SENT.includes(name)) {
                list.push({ fieldName: name, value: values[name] });
            }
        });
        return list;
    }

    plain(values) {
        const out = {};
        Object.keys(values || {}).forEach((k) => {
            if (values[k] !== null && values[k] !== undefined && !NOT_SENT.includes(k)) {
                out[k] = values[k];
            }
        });
        return out;
    }

    notSuggestedNotice(insight) {
        const list = insight.notSuggested || [];
        return list.length ? 'These values could not be suggested and need your input: ' + list.join(', ') + '.' : undefined;
    }

    navigateManual(insight, isUpdate) {
        if (isUpdate && insight.opportunityId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: insight.opportunityId, objectApiName: 'Opportunity', actionName: 'edit' }
            });
            return;
        }
        const values = this.plain(insight.suggestedValues);
        const state = { defaultFieldValues: encodeDefaultFieldValues(values) };
        if (insight.suggestedValues && insight.suggestedValues.RecordTypeId) {
            state.recordTypeId = insight.suggestedValues.RecordTypeId;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Opportunity', actionName: 'new' },
            state
        });
    }

    messageOf(error, fallback) {
        return (error && error.body && error.body.message) || (error && error.message) || fallback;
    }
}

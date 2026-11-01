import { LightningElement, api } from 'lwc';

/**
 * Agent-panel renderer for the "Show Signals" action output (Lightning Type sigSignalCards).
 * It parses the action's cardsJson and hands the cards to the same list component used on
 * record pages, so both surfaces look and behave the same.
 */
export default class SigAgentCards extends LightningElement {
    /** The SigAgentAction.Response object: { cardsJson, summary, count }. */
    @api value;

    get cards() {
        try {
            const parsed = this.value && this.value.cardsJson ? JSON.parse(this.value.cardsJson) : [];
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }

    get recordId() {
        const first = this.cards[0];
        return first ? first.anchorId : undefined;
    }

    get summary() {
        return this.value && this.value.summary;
    }

    get hasCards() {
        return this.cards.length > 0;
    }
}

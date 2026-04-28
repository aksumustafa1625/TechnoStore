import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, getRecordNotifyChange } from 'lightning/uiRecordApi';

import STATUS_FIELD from '@salesforce/schema/Invoice.Stripe_Payment_Status__c';
import URL_FIELD from '@salesforce/schema/Invoice.Stripe_Payment_URL__c';
import INTENT_FIELD from '@salesforce/schema/Invoice.Stripe_Payment_Intent_Id__c';
import PAID_FIELD from '@salesforce/schema/Invoice.Paid_Date__c';
import EMAIL_FIELD from '@salesforce/schema/Invoice.BillToContact.Email';
import MODIFIED_FIELD from '@salesforce/schema/Invoice.LastModifiedDate';

const FIELDS = [STATUS_FIELD, URL_FIELD, INTENT_FIELD, PAID_FIELD, EMAIL_FIELD, MODIFIED_FIELD];
const POLL_INTERVAL_MS = 4000;

export default class PaymentJourney extends LightningElement {
    @api recordId;
    pollHandle;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    invoice;

    connectedCallback() {
        this.pollHandle = setInterval(() => {
            getRecordNotifyChange([{ recordId: this.recordId }]);
        }, POLL_INTERVAL_MS);
    }

    disconnectedCallback() {
        if (this.pollHandle) {
            clearInterval(this.pollHandle);
            this.pollHandle = null;
        }
    }

    get hasData() {
        return this.invoice && this.invoice.data;
    }

    get status() {
        if (!this.hasData) return 'Not Started';
        return getFieldValue(this.invoice.data, STATUS_FIELD) || 'Not Started';
    }

    get hasUrl() {
        return this.hasData && !!getFieldValue(this.invoice.data, URL_FIELD);
    }

    get hasIntentId() {
        return this.hasData && !!getFieldValue(this.invoice.data, INTENT_FIELD);
    }

    get paidDate() {
        return this.hasData ? getFieldValue(this.invoice.data, PAID_FIELD) : null;
    }

    get customerEmail() {
        if (!this.hasData) return 'customer';
        return getFieldValue(this.invoice.data, EMAIL_FIELD) || 'customer';
    }

    get statusBadgeClass() {
        const s = this.status;
        if (s === 'Paid') return 'status-badge status-paid';
        if (s === 'Sent') return 'status-badge status-sent';
        if (s === 'Failed') return 'status-badge status-failed';
        return 'status-badge status-pending';
    }

    get steps() {
        if (!this.hasData) return [];

        const status = this.status;
        const isSent = status === 'Sent' || status === 'Paid';
        const isPaid = status === 'Paid';
        const hasUrl = this.hasUrl;

        const data = [
            {
                key: '1',
                title: 'Sales rep initiates request',
                detail: isSent ? 'Send Payment Link clicked' : 'Click "Send Payment Link" to start',
                done: isSent,
                current: false
            },
            {
                key: '2',
                title: 'Platform Event published',
                detail: isSent ? 'Invoice_Payment_Requested__e fired on the bus' : 'Waiting...',
                done: isSent,
                current: false
            },
            {
                key: '3',
                title: 'MuleSoft subscribes & processes',
                detail: hasUrl ? 'Replay Channel Listener captured the event' : (isSent ? 'In progress...' : 'Waiting'),
                done: hasUrl,
                current: !hasUrl && isSent
            },
            {
                key: '4',
                title: 'Stripe API: POST /v1/checkout/sessions',
                detail: hasUrl ? 'Returned 200 OK with session id' : (isSent ? 'In progress...' : 'Waiting'),
                done: hasUrl,
                current: !hasUrl && isSent
            },
            {
                key: '5',
                title: 'Invoice updated with Stripe URL',
                detail: hasUrl ? 'salesforce:update succeeded' : 'Waiting',
                done: hasUrl,
                current: false
            },
            {
                key: '6',
                title: 'Email sent to customer',
                detail: hasUrl ? 'Sent to ' + this.customerEmail : 'Waiting for URL',
                done: hasUrl,
                current: false
            },
            {
                key: '7',
                title: 'Customer pays at Stripe Checkout',
                detail: isPaid ? 'Payment completed' : (hasUrl ? 'Customer is reviewing the payment page...' : 'Waiting'),
                done: isPaid,
                current: !isPaid && hasUrl
            },
            {
                key: '8',
                title: 'Webhook → Mule → Invoice marked Paid',
                detail: isPaid ? 'Marked Paid at ' + this.formatDate(this.paidDate) : 'Webhook listener idle',
                done: isPaid,
                current: false
            }
        ];

        return data.map(s => ({
            key: s.key,
            title: s.title,
            detail: s.detail,
            itemClass: this.computeClass(s),
            iconName: this.computeIcon(s),
            iconVariant: s.done ? 'success' : (s.current ? 'warning' : '')
        }));
    }

    computeClass(s) {
        if (s.done) return 'journey-item done';
        if (s.current) return 'journey-item current';
        return 'journey-item pending';
    }

    computeIcon(s) {
        if (s.done) return 'utility:success';
        if (s.current) return 'utility:spinner';
        return 'utility:routing_offline';
    }

    formatDate(d) {
        if (!d) return '';
        try {
            const dt = new Date(d);
            return dt.toLocaleString();
        } catch (e) {
            return '';
        }
    }
}

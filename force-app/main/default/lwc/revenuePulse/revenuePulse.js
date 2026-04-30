import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPulseData from '@salesforce/apex/RevenuePulseController.getPulseData';

const POLL_INTERVAL_MS = 5000;
const COUNTER_DURATION_MS = 1200;

export default class RevenuePulse extends LightningElement {
    pollHandle;

    @track displayedTotal = 0;
    @track displayedToday = 0;
    @track displayedCount = 0;
    @track recentActivations = [];
    @track newActivationId = null;
    @track lastSeenIds = new Set();
    @track isLoading = true;
    @track lastUpdated = null;

    targetTotal = 0;
    targetToday = 0;
    targetCount = 0;

    wiredResult;

    @wire(getPulseData)
    wiredPulseData(result) {
        this.wiredResult = result;
        if (result.data) {
            this.handleNewData(result.data);
            this.isLoading = false;
        }
    }

    connectedCallback() {
        this.pollHandle = setInterval(() => {
            refreshApex(this.wiredResult);
        }, POLL_INTERVAL_MS);
    }

    disconnectedCallback() {
        if (this.pollHandle) {
            clearInterval(this.pollHandle);
            this.pollHandle = null;
        }
    }

    handleNewData(data) {
        const previousIds = this.lastSeenIds;
        const newIds = new Set();
        let firstNewId = null;

        const enriched = (data.recentActivations || []).map((act) => {
            newIds.add(act.activationId);
            if (!previousIds.has(act.activationId) && previousIds.size > 0 && !firstNewId) {
                firstNewId = act.activationId;
            }
            const hasSendcloud = !!act.sendcloudCarrier;
            const sendcloudReal = hasSendcloud && act.sendcloudParcelId && !act.sendcloudParcelId.startsWith('LOCAL-');
            const sendcloudLabel = hasSendcloud
                ? (sendcloudReal
                    ? `🚚 ${act.sendcloudCarrier} · #${act.sendcloudParcelId}`
                    : `🚚 ${act.sendcloudCarrier}`)
                : '';
            return {
                ...act,
                isPhysical: act.serviceType === 'Hardware Bundle',
                isDigital: act.serviceType !== 'Hardware Bundle',
                badgeClass: act.serviceType === 'Hardware Bundle' ? 'badge badge-physical' : 'badge badge-digital',
                badgeIcon: act.serviceType === 'Hardware Bundle' ? '📦' : '🔑',
                amountFormatted: this.formatCurrency(act.amount),
                relativeTime: this.formatRelativeTime(act.activationDate),
                rowClass: act.activationId === firstNewId ? 'activation-row pulse-new' : 'activation-row',
                hasSendcloud,
                sendcloudReal,
                sendcloudLabel,
                sendcloudPillClass: sendcloudReal ? 'pill pill-sendcloud pill-real' : 'pill pill-sendcloud'
            };
        });

        this.recentActivations = enriched;
        this.lastSeenIds = newIds;
        this.newActivationId = firstNewId;
        this.lastUpdated = new Date();

        this.targetTotal = data.totalRevenue || 0;
        this.targetToday = data.todayRevenue || 0;
        this.targetCount = data.paidCount || 0;

        this.animateCounter('displayedTotal', this.displayedTotal, this.targetTotal);
        this.animateCounter('displayedToday', this.displayedToday, this.targetToday);
        this.animateCounter('displayedCount', this.displayedCount, this.targetCount, true);
    }

    animateCounter(prop, from, to, isInteger) {
        const start = performance.now();
        const delta = to - from;
        const step = (now) => {
            const elapsed = now - start;
            const progress = Math.min(elapsed / COUNTER_DURATION_MS, 1);
            const eased = 1 - Math.pow(1 - progress, 3);
            const value = from + delta * eased;
            this[prop] = isInteger ? Math.round(value) : value;
            if (progress < 1) {
                requestAnimationFrame(step);
            } else {
                this[prop] = to;
            }
        };
        requestAnimationFrame(step);
    }

    formatCurrency(amount) {
        const n = Number(amount || 0);
        return '$' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    formatRelativeTime(dateStr) {
        if (!dateStr) return 'just now';
        const then = new Date(dateStr);
        const now = new Date();
        const seconds = Math.floor((now - then) / 1000);
        if (seconds < 60) return seconds + 's ago';
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60) return minutes + 'm ago';
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return hours + 'h ago';
        const days = Math.floor(hours / 24);
        return days + 'd ago';
    }

    get totalFormatted() {
        return this.formatCurrency(this.displayedTotal);
    }

    get todayFormatted() {
        return this.formatCurrency(this.displayedToday);
    }

    get hasActivations() {
        return this.recentActivations && this.recentActivations.length > 0;
    }

    get lastUpdatedDisplay() {
        if (!this.lastUpdated) return '—';
        return this.lastUpdated.toLocaleTimeString();
    }
}

import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import exportToDatev from '@salesforce/apex/DatevExportService.exportFromButton';

export default class InvoiceFinanceActions extends LightningElement {
    @api recordId;
    datevLoading = false;
    lastFileName;

    async handleDatev() {
        this.datevLoading = true;
        try {
            const res = await exportToDatev({ invoiceId: this.recordId });
            if (res.status === 'Success') {
                this.lastFileName = res.fileName;
                this.toast('DATEV-Buchungsstapel erstellt', res.message, 'success');
            } else {
                this.toast('DATEV export failed', res.message, 'error');
            }
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (e) {
            this.toast('DATEV error', this.errMsg(e), 'error');
        } finally {
            this.datevLoading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errMsg(e) {
        return e?.body?.message || e?.message || 'Unknown error';
    }
}

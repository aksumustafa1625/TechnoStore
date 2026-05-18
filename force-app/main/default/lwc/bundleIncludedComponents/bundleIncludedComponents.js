import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getBundleComponents from '@salesforce/apex/BundleIncludedComponentsController.getBundleComponents';

export default class BundleIncludedComponents extends LightningElement {
    @api recordId;

    wiredResult;
    bundles;
    error;

    @wire(getBundleComponents, { quoteId: '$recordId' })
    wiredBundles(result) {
        this.wiredResult = result;
        if (result.data) {
            this.bundles = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.bundles = undefined;
        }
    }

    get hasBundles() {
        return this.bundles && this.bundles.length > 0;
    }

    handleRefresh() {
        return refreshApex(this.wiredResult);
    }
}
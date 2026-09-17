/**
 * heldAwayPortfolio.js
 *
 * SECTION 1 — Refresh button
 *   Calls HeldAwayCalloutController.refreshHeldAwayAccounts() imperatively.
 *   After success, calls refreshApex() to force the @wire to re-fetch
 *   updated balances — the table updates automatically with no page reload.
 *
 * SECTION 2 — Portfolio table
 *   Driven by @wire → FinancialAccountsSummaryController.getFinancialSummary()
 *   (cacheable=true). Displays Assets and Liabilities with KPI totals.
 */
import { LightningElement, api, wire } from 'lwc';
import { refreshApex }                 from '@salesforce/apex';
import { ShowToastEvent }              from 'lightning/platformShowToastEvent';
import refreshHeldAwayAccounts from '@salesforce/apex/HeldAwayCalloutController.refreshHeldAwayAccounts';
import getFinancialSummary     from '@salesforce/apex/FinancialAccountsSummaryController.getFinancialSummary';

const ZAR = new Intl.NumberFormat('en-ZA', {
    style: 'currency',
    currency: 'ZAR',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
});

const COLUMNS = [
    { label: 'Account Name', fieldName: 'name',                type: 'text' },
    { label: 'Type',         fieldName: 'financialAccountType', type: 'text' },
    { label: 'Institution',  fieldName: 'institutionName',      type: 'text' },
    {
        label: 'Balance (ZAR)',
        fieldName: 'balance',
        type: 'currency',
        typeAttributes: { currencyCode: 'ZAR', minimumFractionDigits: '2' },
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Held Away',
        fieldName: 'heldAway',
        type: 'boolean',
        cellAttributes: { alignment: 'center' }
    }
];

export default class HeldAwayPortfolio extends LightningElement {

    @api recordId;

    columns = COLUMNS;

    isRefreshing   = false;
    refreshSuccess = false;
    refreshError   = false;
    refreshMessage = '';

    wiredData;

    @wire(getFinancialSummary, { recordId: '$recordId' })
    wiredSummary(result) {
        this.wiredData = result;
    }

    // ── Refresh Button ────────────────────────────────────────────────────────

    handleRefresh() {
        this.refreshSuccess = false;
        this.refreshError   = false;
        this.refreshMessage = '';
        this.isRefreshing   = true;

        refreshHeldAwayAccounts({ recordId: this.recordId })
            .then(result => {
                this.refreshSuccess = true;
                this.refreshMessage = result.message;
                return refreshApex(this.wiredData);
            })
            .then(() => {
                this.isRefreshing = false;
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Accounts Refreshed',
                    message: this.refreshMessage,
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.isRefreshing   = false;
                this.refreshError   = true;
                this.refreshMessage = this._extractError(error);
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Refresh Failed',
                    message: this.refreshMessage,
                    variant: 'error',
                    mode   : 'sticky'
                }));
            });
    }

    // Hides the portfolio while refresh is running — prevents old data flash
    get showPortfolio()  { return !this.isRefreshing; }

    get isLoading()      { return this.wiredData === undefined; }
    get hasError()       { return this.wiredData !== undefined && this.wiredData.error != null; }
    get summary()        { return this.wiredData?.data ?? null; }
    get hasAssets()      { return (this.summary?.assets?.length ?? 0) > 0; }
    get hasLiabilities() { return (this.summary?.liabilities?.length ?? 0) > 0; }
    get hasData()        { return this.summary != null && (this.hasAssets || this.hasLiabilities); }
    get isEmpty()        { return this.summary != null && !this.hasAssets && !this.hasLiabilities; }

    // ── Display Values ────────────────────────────────────────────────────────

    get errorMessage() {
        return this._extractError(this.wiredData?.error);
    }

    get assetCount()                { return this.summary?.assets?.length ?? 0; }
    get liabilityCount()            { return this.summary?.liabilities?.length ?? 0; }
    get formattedTotalAssets()      { return ZAR.format(this.summary?.totalAssets ?? 0); }
    get formattedTotalLiabilities() { return ZAR.format(this.summary?.totalLiabilities ?? 0); }
    get formattedNetWorth()         { return ZAR.format(this.summary?.netWorth ?? 0); }

    get netWorthClass() {
        return (this.summary?.netWorth ?? 0) >= 0
            ? 'slds-text-heading_medium slds-text-color_success'
            : 'slds-text-heading_medium slds-text-color_error';
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    _extractError(error) {
        if (!error) return 'An unexpected error occurred.';
        if (error?.body?.message)  return error.body.message;
        if (typeof error === 'string') return error;
        if (Array.isArray(error?.body) && error.body.length > 0) {
            return error.body.map(e => e.message).join(', ');
        }
        return 'Unable to load financial accounts. Please refresh the page.';
    }
}
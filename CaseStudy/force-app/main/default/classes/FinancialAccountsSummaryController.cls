/**
 * @description  Controller for the financialAccountsSummary LWC.
 *               Returns Financial Accounts for a Person Account split into
 *               Assets and Liabilities, plus a portfolio total.
 *
 */
public with sharing class FinancialAccountsSummaryController {

    // Account types treated as Assets
    private static final Set<String> ASSET_TYPES = new Set<String>{
        'Investment', 'Savings', 'Retirement', 'Bank', 'Checking',
        'Brokerage', 'Education Savings', 'Tax-Free Savings Account'
    };

    // Account types treated as Liabilities
    private static final Set<String> LIABILITY_TYPES = new Set<String>{
        'Loan', 'Mortgage', 'Credit Card', 'Line of Credit',
        'Auto Loan', 'Student Loan', 'Home Equity'
    };

    //Result Wrapper

    public class FinancialSummary {
        @AuraEnabled public List<FinancialAccountRow> assets      { get; set; }
        @AuraEnabled public List<FinancialAccountRow> liabilities { get; set; }
        @AuraEnabled public Decimal totalAssets                   { get; set; }
        @AuraEnabled public Decimal totalLiabilities              { get; set; }
        @AuraEnabled public Decimal netWorth                      { get; set; }

        public FinancialSummary() {
            this.assets         = new List<FinancialAccountRow>();
            this.liabilities    = new List<FinancialAccountRow>();
            this.totalAssets    = 0;
            this.totalLiabilities = 0;
            this.netWorth       = 0;
        }
    }

    public class FinancialAccountRow {
        @AuraEnabled public String  id                  { get; set; }
        @AuraEnabled public String  name                { get; set; }
        @AuraEnabled public String  financialAccountType { get; set; }
        @AuraEnabled public String  institutionName     { get; set; }
        @AuraEnabled public Decimal balance             { get; set; }
        @AuraEnabled public Boolean heldAway            { get; set; }
        @AuraEnabled public String  externalId          { get; set; }
    }

    // @AuraEnabled Method

    /**
     * @description Returns Financial Accounts for the given Person Account,
     *              split into Assets and Liabilities with portfolio totals.
     *
     * @param  recordId  The Person Account Id from the record page.
     * @return FinancialSummary wrapper.
     */
    @AuraEnabled(cacheable=true)
    public static FinancialSummary getFinancialSummary(String recordId) {

        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required.');
        }

        try {
            List<FinServ__FinancialAccount__c> accounts = [
                SELECT Id,
                       Name,
                       FinServ__FinancialAccountType__c,
                       FinServ__Balance__c,
                       FinServ__HeldAway__c,
                       Institution_Name__c,
                       External_Id__c
                FROM   FinServ__FinancialAccount__c
                WHERE  FinServ__PrimaryOwner__c = :recordId
                WITH   USER_MODE
                ORDER BY Name
            ];

            FinancialSummary summary = new FinancialSummary();

            for (FinServ__FinancialAccount__c acc : accounts) {
                FinancialAccountRow row = toRow(acc);
                String accountType = acc.FinServ__FinancialAccountType__c;

                if (LIABILITY_TYPES.contains(accountType)) {
                    summary.liabilities.add(row);
                    summary.totalLiabilities += acc.FinServ__Balance__c != null
                        ? acc.FinServ__Balance__c : 0;
                } else {
                    // Default: treat as asset if type is asset or unknown
                    summary.assets.add(row);
                    summary.totalAssets += acc.FinServ__Balance__c != null
                        ? acc.FinServ__Balance__c : 0;
                }
            }

            summary.netWorth = summary.totalAssets - summary.totalLiabilities;
            return summary;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to load financial accounts: ' + e.getMessage()
            );
        }
    }

    // ── Helper ─────────────────────────────────────────────────────────────────

    private static FinancialAccountRow toRow(FinServ__FinancialAccount__c acc) {
        FinancialAccountRow row    = new FinancialAccountRow();
        row.id                     = acc.Id;
        row.name                   = acc.Name;
        row.financialAccountType   = acc.FinServ__FinancialAccountType__c;
        row.institutionName        = acc.Institution_Name__c;
        row.balance                = acc.FinServ__Balance__c;
        row.heldAway               = acc.FinServ__HeldAway__c;
        row.externalId             = acc.External_Id__c;
        return row;
    }
}
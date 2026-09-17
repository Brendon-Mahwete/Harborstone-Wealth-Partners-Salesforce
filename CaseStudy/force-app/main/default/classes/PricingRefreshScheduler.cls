/**
 * @description  Scheduled Apex job that triggers the nightly held-away account
 *               refresh for all Person Accounts with an External_Id__c set.
 *
 * ─── SCHEDULE ────────────────────────────────────────────────────────────────
 *  Runs nightly at 02:00 AM. To activate, run the following in Execute Anonymous:
 *
 *  System.schedule(
 *      'Nightly Held-Away Account Refresh',
 *      '0 0 2 * * ?',
 *      new PricingRefreshScheduler()
 *  );
 *
 * ─── TO DEACTIVATE ───────────────────────────────────────────────────────────
 *  Setup → Scheduled Jobs → find 'Nightly Held-Away Account Refresh' → Delete
 *
 * ─── WHAT IT DOES ────────────────────────────────────────────────────────────
 *  1. Queries all active Person Accounts that have External_Id__c populated
 *  2. Passes the list of IDs to PricingRefreshQueueable
 *  3. The Queueable processes one account per job execution — no governor limits hit
 *
 * @author   Harborstone Dev
 * @date     2026-09-14
 */
public with sharing class PricingRefreshScheduler implements Schedulable {

    public void execute(SchedulableContext ctx) {

        // Query all Person Accounts with an External_Id__c set
        // These are the clients the external system knows about
        List<Account> accounts = [
            SELECT Id
            FROM   Account
            WHERE  External_Id__c != null
            AND    IsPersonAccount = true
            WITH   USER_MODE
        ];

        if (accounts.isEmpty()) {
            System.debug(LoggingLevel.INFO,
                'PricingRefreshScheduler: No Person Accounts with External_Id__c found. Nothing to process.');
            return;
        }

        // Collect IDs and kick off the Queueable chain
        List<Id> accountIds = new List<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }

        System.debug(LoggingLevel.INFO,
            'PricingRefreshScheduler: Starting nightly refresh for ' +
            accountIds.size() + ' account(s).');

        System.enqueueJob(new PricingRefreshQueueable(accountIds));
    }
}
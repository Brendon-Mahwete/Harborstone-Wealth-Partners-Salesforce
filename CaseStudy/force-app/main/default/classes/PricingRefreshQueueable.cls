/**
 * @description  Queueable Apex job that refreshes held-away Financial Account
 *               data for a list of Person Accounts without hitting governor limits.
 */
public class PricingRefreshQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> accountIds;
    private Integer  currentIndex; 

    // Entry point called by the Scheduler

    public PricingRefreshQueueable(List<Id> accountIds) {
        this(accountIds, 0);
    }

    // Private constructor used by the chain

    private PricingRefreshQueueable(List<Id> accountIds, Integer currentIndex) {
        this.accountIds   = accountIds;
        this.currentIndex = currentIndex;
    }

    // Execute

    public void execute(QueueableContext ctx) {

        // Safety check — nothing left to process
        if (accountIds == null || currentIndex >= accountIds.size()) {
            return;
        }

        Id accountId = accountIds[currentIndex];

        try {
            // Step 1: SOQL the Person Account
            Account acc = [
                SELECT Id, Name, External_Id__c
                FROM   Account
                WHERE  Id = :accountId
                WITH   USER_MODE
                LIMIT  1
            ];

            if (String.isBlank(acc.External_Id__c)) {
                HeldAwayCalloutController.writeLog(
                    null,
                    'SKIPPED — no External_Id__c on Account: ' + acc.Name,
                    0
                );

            } else {

                // Step 2: One callout per execution
                HttpResponse res        = HeldAwayCalloutController.makeCallout(acc.External_Id__c);
                Integer      statusCode = res.getStatusCode();

                if (statusCode == 200) {

                    // Step 3: Parse
                    HeldAwayCalloutController.ApiResponse apiResponse =
                        HeldAwayCalloutController.parseResponse(res.getBody());

                    if (apiResponse?.records != null && !apiResponse.records.isEmpty()) {

                        // Step 4: Upsert (safe — typically 3-20 FAs per client)
                        Integer count = HeldAwayCalloutController.upsertFinancialAccounts(
                            apiResponse.records,
                            acc.Id
                        );

                        // Step 5: Log success
                        HeldAwayCalloutController.writeLog(
                            statusCode,
                            'Nightly batch: refreshed ' + count + ' FA(s) for ' + acc.External_Id__c,
                            0
                        );

                    } else {
                        HeldAwayCalloutController.writeLog(
                            statusCode,
                            'Nightly batch: empty response for ' + acc.External_Id__c,
                            0
                        );
                    }

                } else {
                    // Non-200 — log and continue chain (do not stop other accounts)
                    HeldAwayCalloutController.writeLog(
                        statusCode,
                        'Nightly batch: HTTP ' + statusCode + ' for ' + acc.External_Id__c,
                        0
                    );
                }
            }

        } catch (Exception e) {
            // Per-account error — log and continue to next account
            HeldAwayCalloutController.writeLog(
                null,
                'Nightly batch error for Account ' + accountId + ': ' + e.getMessage(),
                0
            );
        }

        // Step 6: Chain the next job
        if (currentIndex + 1 < accountIds.size()) {
            System.enqueueJob(
                new PricingRefreshQueueable(accountIds, currentIndex + 1)
            );
        }
    }
}
@IsTest
private class PricingRefreshSchedulerTest {

    private static final String CLIENT_EXT_ID = 'CLIENT-PIETER-VDB-001';

    // ── Mock ──────────────────────────────────────────────────────────────────

    private class MockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"clientExternalId":"' + CLIENT_EXT_ID + '",' +
                '"status":"success","totalRecords":0,"records":[]}'
            );
            return res;
        }
    }

    // ── Test Setup ────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        insert new Account(
            LastName       = 'Van der Berg',
            FirstName      = 'Pieter',
            External_Id__c = CLIENT_EXT_ID
        );
    }

    // ── Test 1: Scheduler fires and enqueues the Queueable ────────────────────

    @IsTest
    static void testScheduler_WithAccounts() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            System.schedule(
                'Test Nightly Held-Away Refresh',
                '0 0 2 * * ?',
                new PricingRefreshScheduler()
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, 'Scheduler must run without error');
    }

    // ── Test 2: No accounts with External_Id__c — exits cleanly ──────────────

    @IsTest
    static void testScheduler_NoAccounts() {
        // Remove External_Id__c so no accounts qualify
        Account acc = [SELECT Id FROM Account WHERE External_Id__c = :CLIENT_EXT_ID LIMIT 1];
        acc.External_Id__c = null;
        update acc;

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            System.schedule(
                'Test Nightly Refresh No Accounts',
                '0 0 3 * * ?',
                new PricingRefreshScheduler()
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, 'Should exit cleanly with no accounts to process');
    }
}
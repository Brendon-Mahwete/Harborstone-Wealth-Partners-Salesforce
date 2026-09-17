@IsTest
private class PricingRefreshQueueableTest {

    private static final String CLIENT_EXT_ID = 'CLIENT-PIETER-VDB-001';
    private static final String FA_EXT_ID     = 'FNB-VDB-STOCKBROKING-001';
    private static final Decimal INITIAL_BAL  = 110726.00;
    private static final Decimal UPDATED_BAL  = 118500.00;

    // ── Mocks ─────────────────────────────────────────────────────────────────

    private class MockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"clientExternalId":"' + CLIENT_EXT_ID + '",' +
                '"status":"success","totalRecords":1,"records":[' +
                '{"externalId":"' + FA_EXT_ID + '",' +
                '"name":"FNB Stockbroking","institutionName":"FNB Stockbroking",' +
                '"financialAccountType":"Investment","balance":' + UPDATED_BAL + ',"heldAway":true}]}'
            );
            return res;
        }
    }

    private class Mock404 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{"status":"error","message":"Not found"}');
            return res;
        }
    }

    private class Mock500 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"status":"error","message":"Server error"}');
            return res;
        }
    }

    // ── Test Setup ────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Account client = new Account(
            LastName       = 'Van der Berg',
            FirstName      = 'Pieter',
            External_Id__c = CLIENT_EXT_ID
        );
        insert client;

        Account inserted = [SELECT Id FROM Account WHERE External_Id__c = :CLIENT_EXT_ID LIMIT 1];

        insert new FinServ__FinancialAccount__c(
            Name                             = 'FNB Stockbroking',
            External_Id__c                   = FA_EXT_ID,
            FinServ__PrimaryOwner__c          = inserted.Id,
            FinServ__Balance__c               = INITIAL_BAL,
            FinServ__HeldAway__c              = true,
            Institution_Name__c               = 'FNB'
        );
    }

    // ── Test 1: Success — balance updated in DB ───────────────────────────────

    @IsTest
    static void testExecute_Success() {
        Account acc = getAccount();
        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        System.enqueueJob(new PricingRefreshQueueable(new List<Id>{ acc.Id }));
        Test.stopTest();

        FinServ__FinancialAccount__c fa = [
            SELECT FinServ__Balance__c
            FROM   FinServ__FinancialAccount__c
            WHERE  External_Id__c = :FA_EXT_ID
            LIMIT  1
        ];
        System.assertEquals(UPDATED_BAL, fa.FinServ__Balance__c, 'Balance must be updated');
    }

    // ── Test 2: Account has no External_Id__c — skipped, no exception ─────────

    @IsTest
    static void testExecute_NoExternalId() {
        Account noExtId = new Account(LastName = 'No External ID');
        insert noExtId;

        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            System.enqueueJob(new PricingRefreshQueueable(new List<Id>{ noExtId.Id }));
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, 'Should skip and log — not throw');
    }

    // ── Test 3: HTTP 404 — logs error, chain does not break ───────────────────

    @IsTest
    static void testExecute_404() {
        Account acc = getAccount();
        Test.setMock(HttpCalloutMock.class, new Mock404());

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            System.enqueueJob(new PricingRefreshQueueable(new List<Id>{ acc.Id }));
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, '404 should log error and continue');
    }

    // ── Test 4: HTTP 500 — logs error, chain does not break ───────────────────

    @IsTest
    static void testExecute_500() {
        Account acc = getAccount();
        Test.setMock(HttpCalloutMock.class, new Mock500());

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            System.enqueueJob(new PricingRefreshQueueable(new List<Id>{ acc.Id }));
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, '500 should log error and continue');
    }

    // ── Test 5: Empty list — exits immediately, no exception ──────────────────

    @IsTest
    static void testExecute_EmptyList() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            System.enqueueJob(new PricingRefreshQueueable(new List<Id>()));
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, 'Empty list should exit cleanly');
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private static Account getAccount() {
        return [SELECT Id FROM Account WHERE External_Id__c = :CLIENT_EXT_ID LIMIT 1];
    }
}
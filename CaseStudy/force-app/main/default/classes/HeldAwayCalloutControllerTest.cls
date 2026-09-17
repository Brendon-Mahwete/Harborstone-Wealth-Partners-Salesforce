@IsTest
private class HeldAwayCalloutControllerTest {

    // ── Constants ──────────────────────────────────────────────────────────────
    private static final String  CLIENT_EXT_ID       = 'CLIENT-PIETER-VDB-001';
    private static final String  FA_EXT_ID_FNB       = 'FNB-VDB-STOCKBROKING-001';
    private static final String  FA_EXT_ID_AG        = 'AG-VDB-PERSONAL-001';
    private static final Decimal INITIAL_BALANCE_FNB  = 110726.00;
    private static final Decimal INITIAL_BALANCE_AG   = 113793.00;
    private static final Decimal UPDATED_BALANCE_FNB  = 118500.00;
    private static final Decimal UPDATED_BALANCE_AG   = 121400.00;

    // ── Mocks ──────────────────────────────────────────────────────────────────

    private class MockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assert(
                req.getEndpoint().contains('clientExternalId='),
                'Endpoint must include clientExternalId param'
            );
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(buildSuccessJson());
            return res;
        }
    }

    private class Mock404 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"status":"error","errorCode":"ACCOUNT_NOT_FOUND","message":"Not found."}');
            return res;
        }
    }

    private class Mock500 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"status":"error","errorCode":"INTERNAL_SERVER_ERROR","message":"Error."}');
            return res;
        }
    }

    private class Mock503 implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('{"status":"error","message":"Unavailable."}');
            return res;
        }
    }

    // ── Test Setup ─────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Account clientAccount = new Account(
            LastName       = 'Van der Berg',
            FirstName      = 'Pieter',
            External_Id__c = CLIENT_EXT_ID
        );
        insert clientAccount;

        Account inserted = [
            SELECT Id FROM Account WHERE External_Id__c = :CLIENT_EXT_ID LIMIT 1
        ];

        insert new List<FinServ__FinancialAccount__c>{
            new FinServ__FinancialAccount__c(
                Name                             = 'Van der Berg — FNB Stockbroking',
                External_Id__c                   = FA_EXT_ID_FNB,
                FinServ__PrimaryOwner__c          = inserted.Id,
                FinServ__FinancialAccountType__c  = 'Investment',
                FinServ__Balance__c               = INITIAL_BALANCE_FNB,
                FinServ__HeldAway__c              = true,
                Institution_Name__c               = 'FNB Stockbroking'
            ),
            new FinServ__FinancialAccount__c(
                Name                             = 'Van der Berg — Allan Gray',
                External_Id__c                   = FA_EXT_ID_AG,
                FinServ__PrimaryOwner__c          = inserted.Id,
                FinServ__FinancialAccountType__c  = 'Investment',
                FinServ__Balance__c               = INITIAL_BALANCE_AG,
                FinServ__HeldAway__c              = true,
                Institution_Name__c               = 'Allan Gray'
            )
        };
    }

    // ── Test 1: Success — balances updated in the database ────────────────────

    @IsTest
    static void testSuccess() {
        Account acct = getAccount();
        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        Test.startTest();
        HeldAwayCalloutController.CalloutResult result =
            HeldAwayCalloutController.refreshHeldAwayAccounts(acct.Id);
        Test.stopTest();

        System.assertEquals(true, result.success,         'Expected success = true');
        System.assertEquals(2,    result.recordsUpserted, 'Expected 2 records upserted');

        Map<String, FinServ__FinancialAccount__c> faMap = loadFAs();
        System.assertEquals(UPDATED_BALANCE_FNB,
            faMap.get(FA_EXT_ID_FNB).FinServ__Balance__c, 'FNB balance must be updated');
        System.assertEquals(UPDATED_BALANCE_AG,
            faMap.get(FA_EXT_ID_AG).FinServ__Balance__c,  'Allan Gray balance must be updated');
    }

    // ── Test 2: Idempotency — second upsert must not create duplicates ─────────
    // Salesforce blocks callouts after DML in the same transaction, so we cannot
    // call the full controller twice. We call upsertFinancialAccounts (@TestVisible)
    // directly for the second pass to prove the upsert key prevents duplicates.

    @IsTest
    static void testIdempotent() {
        Account acct = getAccount();
        Test.setMock(HttpCalloutMock.class, new MockSuccess());

        // First call — full controller
        Test.startTest();
        HeldAwayCalloutController.refreshHeldAwayAccounts(acct.Id);
        Test.stopTest();

        System.assertEquals(2, countFAs(), 'Must have exactly 2 records after first call');

        // Second pass — call upsert directly (no callout) to prove no duplicates
        HeldAwayCalloutController.ApiFinancialAccount fnb =
            new HeldAwayCalloutController.ApiFinancialAccount();
        fnb.externalId           = FA_EXT_ID_FNB;
        fnb.name                 = 'Van der Berg — FNB Stockbroking';
        fnb.institutionName      = 'FNB Stockbroking';
        fnb.financialAccountType = 'Investment';
        fnb.balance              = UPDATED_BALANCE_FNB;
        fnb.heldAway             = true;

        HeldAwayCalloutController.ApiFinancialAccount ag =
            new HeldAwayCalloutController.ApiFinancialAccount();
        ag.externalId            = FA_EXT_ID_AG;
        ag.name                  = 'Van der Berg — Allan Gray';
        ag.institutionName       = 'Allan Gray';
        ag.financialAccountType  = 'Investment';
        ag.balance               = UPDATED_BALANCE_AG;
        ag.heldAway              = true;

        HeldAwayCalloutController.upsertFinancialAccounts(
            new List<HeldAwayCalloutController.ApiFinancialAccount>{ fnb, ag },
            acct.Id
        );

        System.assertEquals(2, countFAs(), 'Second upsert must not create duplicates');
    }

    // ── Test 3: Blank record ID → AuraHandledException ────────────────────────
    // NOTE: AuraHandledException.getMessage() always returns "Script-thrown exception"
    // in test context — never assert on the message string. Use a boolean flag instead.

    @IsTest
    static void testBlankRecordId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            HeldAwayCalloutController.refreshHeldAwayAccounts('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected AuraHandledException for blank ID');
    }

    // ── Test 4: Account with no External_Id__c → AuraHandledException ─────────

    @IsTest
    static void testNoExternalId() {
        Account noExtId = new Account(LastName = 'No External ID');
        insert noExtId;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            HeldAwayCalloutController.refreshHeldAwayAccounts(noExtId.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected AuraHandledException for missing External_Id__c');
    }

    // ── Test 5: 404 → AuraHandledException, balances unchanged ───────────────

    @IsTest
    static void test404() {
        Account acct = getAccount();
        Test.setMock(HttpCalloutMock.class, new Mock404());

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            HeldAwayCalloutController.refreshHeldAwayAccounts(acct.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected AuraHandledException for 404');

        // Balances must be unchanged after a failed callout
        Map<String, FinServ__FinancialAccount__c> faMap = loadFAs();
        System.assertEquals(INITIAL_BALANCE_FNB,
            faMap.get(FA_EXT_ID_FNB).FinServ__Balance__c, 'FNB balance must be unchanged after 404');
    }

    // ── Test 6: 500 → AuraHandledException ───────────────────────────────────

    @IsTest
    static void test500() {
        Account acct = getAccount();
        Test.setMock(HttpCalloutMock.class, new Mock500());

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            HeldAwayCalloutController.refreshHeldAwayAccounts(acct.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected AuraHandledException for 500');
    }

    // ── Test 7: 503 → AuraHandledException ───────────────────────────────────

    @IsTest
    static void test503() {
        Account acct = getAccount();
        Test.setMock(HttpCalloutMock.class, new Mock503());

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            HeldAwayCalloutController.refreshHeldAwayAccounts(acct.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected AuraHandledException for 503');
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Account getAccount() {
        return [
            SELECT Id, Name, External_Id__c
            FROM   Account
            WHERE  External_Id__c = :CLIENT_EXT_ID
            LIMIT  1
        ];
    }

    private static Map<String, FinServ__FinancialAccount__c> loadFAs() {
        Map<String, FinServ__FinancialAccount__c> result =
            new Map<String, FinServ__FinancialAccount__c>();
        for (FinServ__FinancialAccount__c fa : [
            SELECT External_Id__c, FinServ__Balance__c
            FROM   FinServ__FinancialAccount__c
            WHERE  External_Id__c IN (:FA_EXT_ID_FNB, :FA_EXT_ID_AG)
        ]) {
            result.put(fa.External_Id__c, fa);
        }
        return result;
    }

    private static Integer countFAs() {
        return [
            SELECT COUNT() FROM FinServ__FinancialAccount__c
            WHERE External_Id__c IN (:FA_EXT_ID_FNB, :FA_EXT_ID_AG)
        ];
    }

    private static String buildSuccessJson() {
        return '{"clientExternalId":"' + CLIENT_EXT_ID + '",'
            + '"clientName":"Pieter Van der Berg","status":"success","totalRecords":2,'
            + '"records":['
            + '{"externalId":"' + FA_EXT_ID_FNB + '",'
            + '"name":"Van der Berg — FNB Stockbroking",'
            + '"institutionName":"FNB Stockbroking","financialAccountType":"Investment",'
            + '"balance":' + UPDATED_BALANCE_FNB + ',"heldAway":true,"lastUpdated":"2026-09-11T02:00:00.000Z"},'
            + '{"externalId":"' + FA_EXT_ID_AG + '",'
            + '"name":"Van der Berg — Allan Gray",'
            + '"institutionName":"Allan Gray","financialAccountType":"Investment",'
            + '"balance":' + UPDATED_BALANCE_AG + ',"heldAway":true,"lastUpdated":"2026-09-11T02:00:00.000Z"}'
            + ']}';
    }
}
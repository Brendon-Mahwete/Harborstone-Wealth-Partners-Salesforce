@IsTest
private class FinancialAccountsSummaryControllerTest {

    // ── Test Setup ─────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // Person Account
        Account client = new Account(
            LastName  = 'Van der Berg',
            FirstName = 'Pieter'
        );
        insert client;

        Account inserted = [SELECT Id FROM Account WHERE LastName = 'Van der Berg' LIMIT 1];

        insert new List<FinServ__FinancialAccount__c>{
            // Assets
            new FinServ__FinancialAccount__c(
                Name                             = 'FNB Stockbroking',
                FinServ__PrimaryOwner__c          = inserted.Id,
                FinServ__FinancialAccountType__c  = 'Investment',
                FinServ__Balance__c               = 118500.00,
                FinServ__HeldAway__c              = true,
                Institution_Name__c               = 'FNB',
                External_Id__c                    = 'FNB-VDB-STOCKBROKING-001'
            ),
            new FinServ__FinancialAccount__c(
                Name                             = 'Allan Gray',
                FinServ__PrimaryOwner__c          = inserted.Id,
                FinServ__FinancialAccountType__c  = 'Investment',
                FinServ__Balance__c               = 121400.00,
                FinServ__HeldAway__c              = true,
                Institution_Name__c               = 'Allan Gray',
                External_Id__c                    = 'AG-VDB-PERSONAL-001'
            ),
            // Liability
            new FinServ__FinancialAccount__c(
                Name                             = 'Home Loan',
                FinServ__PrimaryOwner__c          = inserted.Id,
                FinServ__FinancialAccountType__c  = 'Mortgage',
                FinServ__Balance__c               = 950000.00,
                FinServ__HeldAway__c              = false,
                Institution_Name__c               = 'Standard Bank',
                External_Id__c                    = 'STD-VDB-HOMELOAN-001'
            )
        };
    }

    // ── Test 1: Assets and liabilities split correctly ─────────────────────────

    @IsTest
    static void testGetFinancialSummary_Success() {
        Account client = getClient();
    
        Test.startTest();
        FinancialAccountsSummaryController.FinancialSummary result =
            FinancialAccountsSummaryController.getFinancialSummary(client.Id);
        Test.stopTest();
    
        // Assets
        System.assertEquals(2, result.assets.size(), 'Expected 2 assets');
    
        // Liabilities
        System.assertEquals(1, result.liabilities.size(), 'Expected 1 liability (Mortgage)');
    
        // Totals
        System.assertEquals(239900.00,  result.totalAssets,      'Total assets: 118500 + 121400');
        System.assertEquals(950000.00,  result.totalLiabilities, 'Total liabilities: 950000');
        System.assertEquals(-710100.00, result.netWorth,         'Net worth: assets - liabilities');
    }

    // ── Test 2: Each row has the expected fields populated ─────────────────────

    @IsTest
    static void testGetFinancialSummary_RowFields() {
        Account client = getClient();

        Test.startTest();
        FinancialAccountsSummaryController.FinancialSummary result =
            FinancialAccountsSummaryController.getFinancialSummary(client.Id);
        Test.stopTest();

        FinancialAccountsSummaryController.FinancialAccountRow row = result.assets[0];
        System.assertNotEquals(null, row.id,                  'Row id must not be null');
        System.assertNotEquals(null, row.name,                'Row name must not be null');
        System.assertNotEquals(null, row.financialAccountType,'Row type must not be null');
        System.assertNotEquals(null, row.balance,             'Row balance must not be null');
    }

    // ── Test 3: Account with no Financial Accounts → empty lists ──────────────

    @IsTest
    static void testGetFinancialSummary_NoAccounts() {
        Account emptyClient = new Account(LastName = 'Empty Client');
        insert emptyClient;

        Test.startTest();
        FinancialAccountsSummaryController.FinancialSummary result =
            FinancialAccountsSummaryController.getFinancialSummary(emptyClient.Id);
        Test.stopTest();

        System.assertEquals(0,    result.assets.size(),       'Assets must be empty');
        System.assertEquals(0,    result.liabilities.size(),  'Liabilities must be empty');
        System.assertEquals(0,    result.totalAssets,         'Total assets must be 0');
        System.assertEquals(0,    result.totalLiabilities,    'Total liabilities must be 0');
        System.assertEquals(0,    result.netWorth,            'Net worth must be 0');
    }

    // ── Test 4: Blank record ID → AuraHandledException ────────────────────────

    @IsTest
    static void testGetFinancialSummary_BlankId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            FinancialAccountsSummaryController.getFinancialSummary('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Expected AuraHandledException for blank ID');
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    private static Account getClient() {
        return [SELECT Id FROM Account WHERE LastName = 'Van der Berg' LIMIT 1];
    }
}
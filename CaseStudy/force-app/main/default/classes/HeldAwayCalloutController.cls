/**
 * @description  Controller for the heldAwayPortfolio LWC.
 *
 * Named Credential : Harborstone_Pricing_API
 *
 */
public with sharing class HeldAwayCalloutController {

    // JSON Wrapper Classes

    /**
     * @description Top-level JSON object returned by the external system.
     */
    public class ApiResponse {
        public String                    clientExternalId;
        public String                    clientName;
        public String                    status;
        public Integer                   totalRecords;
        public List<ApiFinancialAccount> records;
    }

    /**
     * @description One Financial Account in the response array.
     *
     */
    public class ApiFinancialAccount {
        public String  externalId;              
        public String  name;
        public String  institutionName;
        public String  financialAccountType;
        public Decimal balance;
        public Boolean heldAway;
        public String  lastUpdated;
    }

    /**
     * @description Result wrapper returned to the LWC.
     */
    public class CalloutResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public Integer recordsUpserted;

        public CalloutResult(Boolean success, String message, Integer recordsUpserted) {
            this.success         = success;
            this.message         = message;
            this.recordsUpserted = recordsUpserted;
        }
    }


    //@AuraEnabled Entry Point

    /**
     * @description Called by the LWC Refresh button.
     *              Pulls the latest held-away account data from the external
     *              system and upserts it into Salesforce as FinServ__FinancialAccount__c records.
     *
     * @param  recordId  The Salesforce Id of the current Person Account record page.
     * @return CalloutResult  Success/error status and count of records upserted.
     */
    @AuraEnabled
    public static CalloutResult refreshHeldAwayAccounts(String recordId) {

        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record ID is required.');
        }

        Integer  httpStatus      = null;
        String   clientExtId     = null;
        String   logErrorMessage = null;

        try {
            Account clientAccount = [
                SELECT Id,
                       Name,
                       External_Id__c
                FROM   Account
                WHERE  Id = :recordId
                WITH   USER_MODE
                LIMIT  1
            ];

            if (String.isBlank(clientAccount.External_Id__c)) {
                throw new AuraHandledException(
                    'This Account does not have a Client External ID (External_Id__c) set. ' +
                    'Please populate it before refreshing.'
                );
            }

            clientExtId = clientAccount.External_Id__c;

            // Step 2: Call external system with the Level 1 External ID
            HttpResponse response    = makeCallout(clientExtId);
            httpStatus               = response.getStatusCode();
            String rawJson           = response.getBody();

            // Step 3: Handle non-200 responses
            if (httpStatus == 404) {
                logErrorMessage = 'ACCOUNT_NOT_FOUND — HTTP 404 for clientExternalId: ' + clientExtId;
                writeLog(httpStatus, logErrorMessage, 0);
                throw new AuraHandledException(
                    'ACCOUNT_NOT_FOUND: No records found in the external system for ' +
                    'Client External ID "' + clientExtId + '". (HTTP 404)'
                );
            } else if (httpStatus != 200) {
                logErrorMessage = 'HTTP ' + httpStatus + ' — ' + rawJson;
                writeLog(httpStatus, logErrorMessage, 0);
                throw new AuraHandledException(
                    'SERVER_ERROR: The external system returned HTTP ' + httpStatus +
                    '. Please try again shortly.'
                );
            }

            // Step 4: Parse the JSON response
            ApiResponse apiResponse = parseResponse(rawJson);

            if (apiResponse == null
             || apiResponse.records == null
             || apiResponse.records.isEmpty()) {
                writeLog(httpStatus, 'Empty records returned for: ' + clientExtId, 0);
                return new CalloutResult(
                    false,
                    'The external system returned no financial accounts for this client.',
                    0
                );
            }

            //Step 5: Upsert FAs using each record's Level 2 externalId
            Integer upsertCount = upsertFinancialAccounts(
                apiResponse.records,
                clientAccount.Id
            );

            //Step 6: Log success
            writeLog(
                httpStatus,
                'SUCCESS — refreshed ' + upsertCount + ' FA(s) for ' + clientExtId,
                0
            );

            return new CalloutResult(
                true,
                'Successfully refreshed ' + upsertCount +
                ' held-away account(s) for ' + clientAccount.Name + '.',
                upsertCount
            );

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (System.CalloutException ce) {
            writeLog(httpStatus, ce.getMessage(), 0);
            throw new AuraHandledException(ce.getMessage());
        } catch (System.JSONException je) {
            writeLog(httpStatus, 'JSON parse error: ' + je.getMessage(), 0);
            throw new AuraHandledException(
                'Could not read the response from the external system. Details: ' +
                je.getMessage()
            );
        } catch (System.QueryException qe) {
            throw new AuraHandledException(
                'Could not find the Account record. Details: ' + qe.getMessage()
            );
        } catch (DmlException de) {
            writeLog(httpStatus, 'DML error: ' + de.getMessage(), 0);
            throw new AuraHandledException(
                'Failed to save records to Salesforce. Details: ' + de.getMessage()
            );
        } catch (Exception e) {
            writeLog(httpStatus, 'Unexpected error: ' + e.getMessage(), 0);
            throw new AuraHandledException('Unexpected error: ' + e.getMessage());
        }
    }


    //Public Helpers (reused by PricingRefreshQueueable)

    /**
     * @description HTTP GET callout to the external system.
     *              Returns the full HttpResponse so the caller can read
     *              the status code and body separately.
     */
    @TestVisible
    public static HttpResponse makeCallout(String clientExternalId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'callout:Harborstone_Pricing_API/financial-accounts?clientExternalId=' +
            EncodingUtil.urlEncode(clientExternalId, 'UTF-8')
        );
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(10000);
        return new Http().send(req);
    }

    /**
     * @description Deserialises the raw JSON into the ApiResponse wrapper.
     */
    @TestVisible
    public static ApiResponse parseResponse(String jsonBody) {
        return (ApiResponse) JSON.deserialize(jsonBody, ApiResponse.class);
    }

    /**
     * @description Maps API records to FinServ__FinancialAccount__c SObjects
     *              and bulk-upserts using the Level 2 externalId as the match key.
     *
     * @param  apiAccounts    List of accounts from the external system response.
     * @param  primaryOwnerId The Person Account Id to link each FA to.
     * @return Integer        Number of successfully upserted records.
     */
    @TestVisible
    public static Integer upsertFinancialAccounts(List<ApiFinancialAccount> apiAccounts,Id primaryOwnerId) {
        List<FinServ__FinancialAccount__c> toUpsert =
            new List<FinServ__FinancialAccount__c>();

        for (ApiFinancialAccount apiAcc : apiAccounts) {
            toUpsert.add(new FinServ__FinancialAccount__c(
                External_Id__c                   = apiAcc.externalId,
                Name                             = apiAcc.name,
                FinServ__Balance__c              = apiAcc.balance,
                FinServ__HeldAway__c             = apiAcc.heldAway != null? apiAcc.heldAway : true,
                FinServ__FinancialAccountType__c = apiAcc.financialAccountType,
                Institution_Name__c              = apiAcc.institutionName,
                FinServ__PrimaryOwner__c         = primaryOwnerId
            ));
        }

        Integer successCount = 0;

        if (!toUpsert.isEmpty()) {
            List<Database.UpsertResult> results = Database.upsert(
                toUpsert,
                FinServ__FinancialAccount__c.External_Id__c,
                false
            );

            for (Database.UpsertResult ur : results) {
                if (ur.isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error err : ur.getErrors()) {
                        System.debug(LoggingLevel.WARN,
                            'Upsert row error [' + err.getStatusCode() + ']: ' +
                            err.getMessage());
                    }
                }
            }
        }

        return successCount;
    }

    /**
     * @description Writes one Asset_Pricing_Log__c record to track this callout.
     *              Wrapped in its own try/catch so a logging failure never
     *              breaks the main integration flow.
     *
     * @param  httpStatusCode  The HTTP status code returned by the external system.
     * @param  detail          Success summary or error message to store.
     * @param  retryCount      Number of retry attempts (0 for first attempt).
     */
    @TestVisible
    public static void writeLog(Integer httpStatusCode, String detail, Integer retryCount) {
        try {
            insert new Asset_Pricing_Log__c(
                Request_Timestamp__c = DateTime.now(),
                HTTP_Status_Code__c  = httpStatusCode,
                Error_Message__c     = detail,
                Retry_Count__c       = retryCount != null ? retryCount : 0
                // Financial_Holding__c is null — not applicable at Financial Account level
            );
        } catch (Exception e) {
            // Logging failure must never surface to the user
            System.debug(LoggingLevel.WARN,
                'Asset_Pricing_Log__c insert failed (non-fatal): ' + e.getMessage());
        }
    }
}
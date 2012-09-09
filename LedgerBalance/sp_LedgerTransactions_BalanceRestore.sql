USE [DebtManager]
GO

/****** Object:  StoredProcedure [dbo].[spLedgerTransaction_BalanceRestore]    Script Date: 09/09/2012 07:04:46 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[spLedgerTransaction_BalanceRestore] (
	@AccountUid uniqueidentifier = null,
	@SessionCountToIgnore int = 3,
	@MaxAccountsToConsider int = 400,
	@MaxBalanceForwardsToConsider int = -1
)
AS

-- =========================================================================
-- Authors:		SBering, JMonroe, TSidhu, KLomax
-- Create date: 1/6/2011
-- Last Modified: 3/2/2011
-- Description:	Restores the DebtManager LedgerTransaction TABLE by removing 
--              a previous fix for out of balance reserve balances and, 
--              by context, inserting the transactions FROM DebtSettlement
--
-- Modified: 9/15/2011 - Added support for 800 transactions and logging
-- =========================================================================

SET NOCOUNT ON;
/*
DECLARE @AccountUid uniqueidentifier, @SessionCountToIgnore int, @MaxAccountsToConsider int
SET @AccountUid = '8CA2B2A7-B991-DF11-9D1A-0015C5F39DA6'
SET @SessionCountToIgnore = 3
SET @MaxAccountsToConsider = 400
SET NOCOUNT OFF;
--*/
-----------------------------------------------------------------------------------
-- Create AuditSession 
-----------------------------------------------------------------------------------
INSERT LedgerTransactions_AuditSession(SessionDate) VALUES(GetDate())

SELECT SessionId = SCOPE_IDENTITY()
INTO #AuditSession

--------------------------------------------------------------------------------------------------------------------------------
-- Getting accounts and transactions to restore
--------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE #AccountsToRestore(
	[AccountUid] [uniqueidentifier] NOT NULL,
	[DmAccountId] [int] NOT NULL,
	[DmReserveBalance] [money] NOT NULL,
	[DsAccountId] [int] NOT NULL,
	[DsReserveBalance] [numeric](18, 2) NOT NULL,
	[AdjustedReserveBalance] [numeric](38, 2) NULL,
	[DsContactId] [int] NOT NULL
) 

CREATE TABLE #BalanceForwardAccounts(
	[AccountId] [int] NOT NULL
)


IF (@AccountUid IS NOT NULL) BEGIN

	INSERT #AccountsToRestore(AccountUid,DmAccountId,DmReserveBalance,DsAccountId,DsReserveBalance,AdjustedReserveBalance,DsContactId)
		SELECT
		DmAccounts.AccountUid, 
		DmAccounts.AccountId 'DmAccountId',
		DmAccounts.AccountCurrentReserveBalance 'DmReserveBalance',
		DsAccounts.AccountId 'DsAccountId',
		DsAccounts.ReserveBalance 'DsReserveBalance',
		AdjustedReserveBalance = DsAccounts.ReserveBalance - ISNULL(Advances.AdvanceBalance, 0),
		DsAccounts.ContactId 'DsContactId'
		FROM Account DmAccounts
		INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts DsAccounts ON DmAccounts.AccountUid = DsAccounts.AccountGuid
		LEFT JOIN DebtSettlementLink.DebtSettlement.dbo.vCorporateAdvancesByAccount Advances ON DsAccounts.AccountId = Advances.AccountId
		WHERE AccountUid = @AccountUid

	INSERT #BalanceForwardAccounts(AccountId)
		SELECT AccountId
		FROM LedgerTransactions 
		WHERE Description = 'Balance Forward'
		AND AccountID = (
			SELECT AccountID 
			FROM Account 
			WHERE AccountUid = @AccountUid
			)

END
ELSE BEGIN

	INSERT #AccountsToRestore(AccountUid,DmAccountId,DmReserveBalance,DsAccountId,DsReserveBalance,AdjustedReserveBalance,DsContactId)
		SELECT
		DmAccounts.AccountUid, 
		DmAccounts.AccountId 'DmAccountId',
		DmAccounts.AccountCurrentReserveBalance 'DmReserveBalance',
		DsAccounts.AccountId 'DsAccountId',
		DsAccounts.ReserveBalance 'DsReserveBalance',
		AdjustedReserveBalance = DsAccounts.ReserveBalance - ISNULL(Advances.AdvanceBalance, 0),
		DsAccounts.ContactId 'DsContactId'
		FROM Account DmAccounts
		INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts DsAccounts ON DmAccounts.AccountUid = DsAccounts.AccountGuid
		LEFT JOIN DebtSettlementLink.DebtSettlement.dbo.vCorporateAdvancesByAccount Advances ON DsAccounts.AccountId = Advances.AccountId

	-- if default value for balance forwards, add all balance forwards to list
	IF (@MaxBalanceForwardsToConsider = -1)
	BEGIN
		INSERT #BalanceForwardAccounts(AccountId)
		SELECT AccountId
		FROM LedgerTransactions 
		WHERE Description = 'Balance Forward'
	END

	-- if value for balance forwards provided, add subset of balance forwards to list
	IF (@MaxBalanceForwardsToConsider > 0)
	BEGIN
		INSERT #BalanceForwardAccounts(AccountId)
		SELECT TOP (@MaxBalanceForwardsToConsider) AccountId
		FROM LedgerTransactions 
		WHERE Description = 'Balance Forward'
	END

END
-- SELECT * FROM #AccountsToRestore

CREATE Unique NonClustered INDEX idx_DmAccountId ON #AccountsToRestore(DmAccountId)
CREATE Unique NonClustered INDEX idx_DsAccountId ON #AccountsToRestore(DsAccountId)
CREATE Unique NonClustered INDEX idx_AccountUid ON #AccountsToRestore(AccountUid)


DELETE FROM #AccountsToRestore -- SELECT COUNT(*) FROM #AccountsToRestore
WHERE DmAccountId NOT IN (
	SELECT AccountId FROM #BalanceForwardAccounts
	)
AND DmReserveBalance = AdjustedReserveBalance

-----------------------------------------------------------------------------------
-- ### Update AuditSession ###
-----------------------------------------------------------------------------------
UPDATE LedgerTransactions_AuditSession SET 
	AccountsToRestoreTotal = (SELECT COUNT(*) FROM #AccountsToRestore),
	BalanceForwardAccounts = (SELECT COUNT(*) FROM #BalanceForwardAccounts)
WHERE SessionId = (
	SELECT SessionId FROM #AuditSession
	)

-----------------------------------------------------------------------------------
-- Limit Accounts to Process
-----------------------------------------------------------------------------------
IF (@AccountUid IS NULL) BEGIN

		IF ((SELECT COUNT(*) FROM #AccountsToRestore) > @MaxAccountsToConsider) BEGIN

			DECLARE @RangeLow int, @RangeHigh int, @AccountRestoreCount int, @OffsetCount int
			SELECT @RangeLow = SessionId - @SessionCountToIgnore, @RangeHigh = SessionId - 1 FROM #AuditSession
			SELECT @AccountRestoreCount = COUNT(*) FROM #AccountsToRestore
			SET @OffsetCount = @AccountRestoreCount - @MaxAccountsToConsider
			
			SELECT AccountID
			INTO #AccountsToRestoreDropList
			FROM LedgerTransactions_AuditHistory 
			WHERE SessionId BETWEEN @RangeLow AND @RangeHigh
			ORDER BY ID DESC

			DELETE FROM #AccountsToRestore
			WHERE DmAccountId IN (
				SELECT TOP (@OffsetCount) AccountID FROM #AccountsToRestoreDropList
				)
				
			PRINT CAST(@@RowCount AS varchar(10)) + ' previously processed accounts removed from AccountsToRestore list'
		END

		IF ((SELECT COUNT(*) FROM #AccountsToRestore) > @MaxAccountsToConsider) BEGIN

			DELETE TOP((SELECT COUNT(*) FROM #AccountsToRestore)- @MaxAccountsToConsider) FROM #AccountsToRestore

			PRINT CAST(@@RowCount AS varchar(10)) + ' accounts removed from AccountsToRestore list'
		END

END



-----------------------------------------------------------------------------------
-- Build master transaction  list
-----------------------------------------------------------------------------------
SELECT DISTINCT *
INTO #DsTransactions --SELECT DISTINCT *
FROM (
	SELECT TransactionId, ParentTransactionId, TransactionGuid, AccountId, DisbursementAccountId, ReceiptId, TransactionTypeId, Amount, IsReallocated, IsClearedForGoodFunds, IsReversed, TransactionTypeGuid, AllocationTypeId, CreationDateTime, LastEditDateTime
	FROM DebtSettlementLink.DebtSettlement.dbo.VTransactionsLedgerView Trans WITH (NOLOCK)
	INNER JOIN #AccountsToRestore ON Trans.AccountId = #AccountsToRestore.DsAccountId

	UNION

	SELECT TransactionId, ParentTransactionId, TransactionGuid, AccountId, DisbursementAccountId, ReceiptId, TransactionTypeId, Amount, IsReallocated, IsClearedForGoodFunds, IsReversed, TransactionTypeGuid, AllocationTypeId, CreationDateTime, LastEditDateTime
	FROM DebtSettlementLink.DebtSettlement.dbo.VTransactionsLedgerView Trans WITH (NOLOCK)
	INNER JOIN #AccountsToRestore ON Trans.DisbursementAccountId = #AccountsToRestore.DsAccountId
	) T1

CREATE Unique NonClustered INDEX idx_TransactionId ON #DsTransactions(TransactionId)
CREATE NonClustered INDEX idx_ParentTransactionId ON #DsTransactions(ParentTransactionId)

-- Remove accounts with recent transactions < 15 minutes ago

DELETE FROM #AccountsToRestore
WHERE DmAccountId IN (
	SELECT DISTINCT DmAccountId 
	FROM #DsTransactions dsTrans
	INNER JOIN #AccountsToRestore atr ON dsTrans.AccountId = atr.DsAccountId
	WHERE DATEDIFF(mi, dsTrans.LastEditDateTime, GETDATE()) < 15
	)

PRINT CAST(@@RowCount AS varchar(10)) + ' accounts removed from AccountsToRestore list for recent transactions'


-----------------------------------------------------------------------------------
-- ### Update AuditSession ###
-----------------------------------------------------------------------------------
UPDATE LedgerTransactions_AuditSession SET 
	AccountsConsidered = (SELECT COUNT(*) FROM #AccountsToRestore)
WHERE SessionId = (
	SELECT SessionId FROM #AuditSession
	)
-----------------------------------------------------------------------------------

						
DECLARE @total int 
SELECT @total = COUNT(*) FROM #AccountsToRestore
DECLARE @balfor int
SELECT @balfor = COUNT(*) FROM #BalanceForwardAccounts
DECLARE @outsync int
SET @outsync = @total - @balfor
PRINT CAST(@balfor AS varchar(5)) + ' Balance-Forward accounts'
PRINT CAST(@outsync AS varchar(5)) + ' out-of-sync accounts'
PRINT CAST(@total AS varchar(10)) + ' total account ledgers to restore'
PRINT ' '



--------------------------------------------------------------------------------------------------------------------------------
--Create custom filters for transactions
--------------------------------------------------------------------------------------------------------------------------------

--Remove fees going to the consumer account when it is not a reversed transaction--bug?
--because this situation actually increases the reserve balance of the account so should not be shown
DELETE FROM #DsTransactions
WHERE TransactionId IN (
	SELECT TransactionId 
	FROM #DsTransactions 
	WHERE TransactionTypeId = 634 
	AND IsReversed = 0
	AND AccountId = DisbursementAccountId
	)



--Get all 638 and corresponding 649 transactions if those exist
--even split 649 fees
SELECT 
TransactionId, ParentTransactionId, Amount, AccountId, DisbursementAccountId, CreationDateTime, IsReversed
INTO #Nwr638Fees
FROM #DsTransactions
WHERE TransactionTypeId = 638

SELECT 
TransactionId 'cTransactionId',
ParentTransactionId 'cParentTransactionId', 
Amount 'cAmount', 
AccountId 'cAccountId', 
DisbursementAccountId 'cDisbursementAccountId', 
CreationDateTime 'cCreationDateTime', 
IsReversed 'cIsReversed'
INTO #Nwr649Fees
FROM #DsTransactions
WHERE TransactionTypeId = 649

SELECT *
INTO #NwrFees
FROM #Nwr638Fees
LEFT JOIN #Nwr649Fees
ON DATEDIFF(s, cCreationDateTime, CreationDateTime) < 90
AND (Amount = cAmount * -1 OR Amount < cAmount * -1)
AND IsReversed = cIsReversed
AND ParentTransactionId = cParentTransactionId
AND TransactionId > cTransactionId
AND cDisbursementAccountId <> 2

SELECT *
INTO #NwrFeesToRemoveFromLedger -- SELECT *
FROM #NwrFees
WHERE cAccountId <> cDisbursementAccountId
AND Amount = cAmount * -1

DELETE FROM #DsTransactions -- those fees paid by DSCs
WHERE TransactionId IN (SELECT TransactionId FROM #NwrFeesToRemoveFromLedger)

UPDATE #DsTransactions -- that are partially paid by other DSCs
SET Amount = LoweredAmount
FROM (SELECT TransactionId 'nwrId', Amount + SUM(cAmount) 'LoweredAmount'
		FROM #NwrFees
		WHERE cAccountId <> cDisbursementAccountId
		GROUP BY TransactionId, Amount) nwr
WHERE TransactionId = nwrId


--SELECT * FROM #DsTransactions WHERE TransactionTypeId = 638
DROP TABLE #Nwr638Fees
DROP TABLE #Nwr649Fees
DROP TABLE #NwrFees
DROP TABLE #NwrFeesToRemoveFromLedger

--Get all 669 and corresponding 649 transactions if those exist
--even split 649 fees, just as did before with the 638 transactions

SELECT 
TransactionId, ParentTransactionId, Amount, AccountId, DisbursementAccountId, CreationDateTime, IsReversed
INTO #Nwr669Fees
FROM #DsTransactions
WHERE TransactionTypeId = 669

SELECT 
TransactionId 'cTransactionId',
ParentTransactionId 'cParentTransactionId', 
Amount 'cAmount', 
AccountId 'cAccountId', 
DisbursementAccountId 'cDisbursementAccountId', 
CreationDateTime 'cCreationDateTime', 
IsReversed 'cIsReversed'
INTO #NwrManual649Fees
FROM #DsTransactions
WHERE TransactionTypeId = 649

SELECT *
INTO #NwrManualFees
FROM #Nwr669Fees
LEFT JOIN #NwrManual649Fees
ON DATEDIFF(s, cCreationDateTime, CreationDateTime) < 90
AND (Amount = cAmount * -1 OR Amount < cAmount * -1)
AND IsReversed = cIsReversed
AND ParentTransactionId = cParentTransactionId
--AND TransactionId > cTransactionId

SELECT *
INTO #NwrManualFeesToRemoveFromLedger -- SELECT *
FROM #NwrManualFees
WHERE cAccountId <> cDisbursementAccountId
AND Amount = cAmount * -1

DELETE FROM #DsTransactions -- those fees paid by DSCs
WHERE TransactionId IN (SELECT TransactionId FROM #NwrManualFeesToRemoveFromLedger)

UPDATE #DsTransactions -- that are partially paid by other DSCs
SET Amount = LoweredAmount
FROM (SELECT TransactionId 'nwrId', Amount + SUM(cAmount) 'LoweredAmount'
		FROM #NwrManualFees
		WHERE cAccountId <> cDisbursementAccountId
		GROUP BY TransactionId, Amount) nwr
WHERE TransactionId = nwrId


--SELECT * FROM #DsTransactions WHERE TransactionTypeId = 638
DROP TABLE #Nwr669Fees
DROP TABLE #NwrManual649Fees
DROP TABLE #NwrManualFees
DROP TABLE #NwrManualFeesToRemoveFromLedger

--Remove fees that are reallocated

DELETE --SELECT *
FROM #DsTransactions
WHERE IsReallocated = 1
AND AccountId <> DisbursementAccountId


--Remove 631 Transactions where AccountId = DisbursmentAccountId
DELETE --SELECT *
FROM #DsTransactions
WHERE TransactionTypeId = 631
AND AccountId = DisbursementAccountId

--Remove 635 Transactions where AccountId = DisbursmentAccountId

DELETE --SELECT *
FROM #DsTransactions
WHERE TransactionTypeId = 635
AND AccountId = DisbursementAccountId

--End Customization



--------------------------------------------------------------------------------------------------------------------------------
--Create DebtManager filters for transactions
--------------------------------------------------------------------------------------------------------------------------------
--Get parent transactions by ContextType FROM the DebtSetttlement #DsTransactions

SELECT * 
INTO #PaymentParents -- SELECT *
FROM #DsTransactions
WHERE ParentTransactionId is null
AND TransactionTypeId in (601, 602, 603)

SELECT *
INTO #DisbursementParents -- SELECT *
FROM #DsTransactions
WHERE ParentTransactionId is null
AND TransactionTypeId = 651

--Index #DisbursementParents--the only TABLE NOT empty
CREATE UNIQUE INDEX idx_ptr ON #DisbursementParents(TransactionId)

SELECT * 
INTO #AdjustmentParents -- SELECT *
FROM #DsTransactions
WHERE ParentTransactionId is null
AND TransactionTypeId in (600, 646, 636, 650, 700) 

--SELECT TransactionId FROM #AdjustmentParents
--Begin Customization, but Steve already took care of this (2/15/2011)
SELECT * 
INTO #TransferParents -- SELECT *
FROM #DsTransactions
WHERE ParentTransactionId is null
AND TransactionTypeId in (652)

SELECT * 
INTO #NewTransferParents -- SELECT *
FROM #DsTransactions
WHERE ParentTransactionId is null
AND TransactionTypeId in (800,801,802,803,804,805,806,807,808,809)


--End Customization

--SELECT * FROM #TransferParents
--SELECT * FROM #NewTransferParents

--By context type, get a list of parent transactions that need to be removed after a substitute is selected AND children are updated.  --Should only be Disbursements

SELECT t1.*, t2.Id
INTO #PaymentParentsToRemove -- SELECT *
FROM #PaymentParents t1
JOIN TransactionContextTransactionTypes t2 WITH (NOLOCK) ON t1.TransactionTypeId = t2.TransactionTypeId AND t2.TransactionContextId = 1
WHERE t2.Id = null

SELECT t1.*, t2.Id
INTO #DisbursementParentsToRemove -- SELECT *
FROM #DisbursementParents t1
LEFT JOIN TransactionContextTransactionTypes t2 WITH (NOLOCK) ON t1.TransactionTypeId = t2.TransactionTypeId AND t2.TransactionContextId = 2
WHERE t2.Id is null

SELECT t1.*, t2.Id
INTO #AdjustmentParentsToRemove -- SELECT *
FROM #AdjustmentParents t1
LEFT JOIN TransactionContextTransactionTypes t2 WITH (NOLOCK) ON t1.TransactionTypeId = t2.TransactionTypeId AND t2.TransactionContextId = 3
WHERE t2.Id is null

SELECT t1.*, t2.Id
INTO #TransferParentsToRemove -- SELECT *
FROM #TransferParents t1
LEFT JOIN TransactionContextTransactionTypes t2 WITH (NOLOCK) ON t1.TransactionTypeId = t2.TransactionTypeId AND t2.TransactionContextId = 4
WHERE t2.Id is null

SELECT t1.*, t2.Id
INTO #NewTransferParentsToRemove -- SELECT *
FROM #NewTransferParents t1
LEFT JOIN TransactionContextTransactionTypes t2 WITH (NOLOCK) ON t1.TransactionTypeId = t2.TransactionTypeId AND t2.TransactionContextId = 4
WHERE t2.Id is null



--Join all ParentsToRemove
SELECT IDENTITY(INT, 1, 1) AS Row, t1.*
INTO #ParentsToRemove -- SELECT *
FROM (SELECT * FROM #PaymentParentsToRemove
UNION SELECT * FROM #DisbursementParentsToRemove
UNION SELECT * FROM #AdjustmentParentsToRemove
UNION SELECT * FROM #TransferParentsToRemove
UNION SELECT * FROM #NewTransferParentsToRemove) t1

--SELECT * FROM #DsTransactions
--SELECT * FROM #ParentsToRemove

DROP TABLE #DisbursementParentsToRemove
DROP TABLE #PaymentParentsToRemove
DROP TABLE #AdjustmentParentsToRemove
DROP TABLE #TransferParentsToRemove
DROP TABLE #NewTransferParentsToRemove

--By parent contexts, get a list of children, NOT listed in the context, to remove


--transactions to remove that do not belong to the payment context
--AND to remove 638 transactions paid to payer's account
SELECT t1.* 
INTO #PaymentChildrenToRemove -- SELECT *
FROM #DsTransactions t1
JOIN #PaymentParents t2 ON t1.ParentTransactionId = t2.TransactionId
LEFT JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 1
WHERE t3.Id is null

UNION all

SELECT t1.* FROM #DsTransactions t1
JOIN #PaymentParents t2 ON t1.ParentTransactionId = t2.TransactionId
INNER JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 1
WHERE t1.TransactionTypeId = 638
AND t1.DisbursementAccountId = t1.AccountId

--SELECT * FROM #DsTransactions WHERE TransactionTypeId = 638

--SELECT * FROM #PaymentChildrenToRemove
--

--helps get payment parents of 620 Reserve Credits
--but doesn't help if the funds orginally were paid by DSC

--Begin Customization, This no longer occurs on new transactions but is needed for existing ones
SELECT ParentTransactionId, Amount
INTO #FeeReallocationParents
FROM #DsTransactions
WHERE TransactionTypeId = 649
AND DisbursementAccountId = 2

/*Accessing #FeeReallocationParents
SELECT * FROM #DsTransactions WHERE TransactionTypeId = 649
SELECT ParentTransactionId FROM #FeeReallocationParents
*/


DELETE FROM #PaymentChildrenToRemove
WHERE TransactionId IN (
	SELECT t1.TransactionId 
	FROM #DsTransactions t1
	INNER JOIN #FeeReallocationParents t2 ON t1.ParentTransactionId = t2.ParentTransactionId
	WHERE t1.TransactionTypeId = 620
	AND t1.DisbursementAccountId = t1.AccountId
	AND t2.Amount = (-1 * t1.Amount)
	)
						
--Get 620s that have possibly been used to adjust the ledger to balance a NoteWorld processing fee origionally paid by the DSC

SELECT --620 transactions that IsReversed IS NULL (pre-dates the use of IsReversed)
TransactionId, ParentTransactionId, Amount, AccountId, DisbursementAccountId, CreationDateTime
INTO #ReserveCreditAdjustments --Select *
FROM #DsTransactions
WHERE TransactionTypeId = 620
AND IsReversed = 0
AND Amount > 0

						
--Get 649 transactions that are used to distribute full or partial funds back to the DSC after a returned payment and
--before a 620 is used to take the funds for that payment from the consumer account

SELECT --649 transactions that IsReversed IS NULL (pre-dates the use of IsReversed)
TransactionId 'cTransactionId',
ParentTransactionId 'cParentTransactionId', 
Amount 'cAmount', 
AccountId 'cAccountId', 
DisbursementAccountId 'cDisbursementAccountId',
CreationDateTime 'cCreationDateTime'
INTO #NwrAssessedFeeReversals -- SELECT *
FROM #DsTransactions 
WHERE TransactionTypeId = 649
AND IsReversed = 0
AND Amount < 0

--matchup the adjustments so that partial fee reinbursement amounts can be used
SELECT *
INTO #NwrAssessedFeeAdjustments -- SELECT *
FROM #ReserveCreditAdjustments rca
INNER JOIN #NwrAssessedFeeReversals nafr 
ON rca.ParentTransactionId = nafr.cParentTransactionId
AND DATEDIFF(mi, cCreationDateTime, CreationDateTime) > 2

--remove the payment children of the 620 transaction so that the 620 will remain in the ledger

DELETE -- Select *
FROM #PaymentChildrenToRemove
WHERE TransactionId IN (SELECT TransactionId FROM #NwrAssessedFeeAdjustments)

--Get transaction ids and amounts that need adjustment

SELECT TransactionId 'AdjustmentTransactionId', cAmount 'AdjustmentAmount'
INTO #AmountAdjustments -- SELECT *
FROM #NwrAssessedFeeAdjustments
WHERE Amount + cAmount * -1 <> 0

--adjust the amount on the 620 just in case the associative 649 is only a partial reinbursement

UPDATE #DsTransactions
SET Amount = AdjustmentAmount
FROM #AmountAdjustments
WHERE TransactionId = AdjustmentTransactionId

DROP TABLE #ReserveCreditAdjustments
DROP TABLE #NwrAssessedFeeReversals
DROP TABLE #NwrAssessedFeeAdjustments
DROP TABLE #AmountAdjustments
--*/
--End of Customization

--Begin Customization 622 transaction conflict
--Allow 622 reserve credit fee transactions when it is a refund of an overpayment or a reversal

SELECT 
TransactionId, ParentTransactionId, Amount, AccountId, DisbursementAccountId, CreationDateTime
INTO #Nwr622Fees
FROM #DsTransactions
WHERE TransactionTypeId = 622

SELECT 
TransactionId 'cTransactionId',
ParentTransactionId 'cParentTransactionId', 
Amount 'cAmount', 
AccountId 'cAccountId', 
DisbursementAccountId 'cDisbursementAccountId', 
CreationDateTime 'cCreationDateTime'
INTO #Nwr649Adjustments
FROM #DsTransactions
WHERE TransactionTypeId = 649

SELECT *
INTO #NwrAdjustmentFees -- SELECT *
FROM #Nwr622Fees
INNER JOIN #Nwr649Adjustments
ON DATEDIFF(s, CreationDateTime, cCreationDateTime) < 90
AND Amount = cAmount * -1
AND ParentTransactionId = cParentTransactionId
--AND TransactionId > cTransactionId

DELETE FROM #PaymentChildrenToRemove
WHERE TransactionId IN (SELECT TransactionId FROM #NwrAdjustmentFees)

UPDATE #DsTransactions
SET Amount = Amount * -1
WHERE TransactionId IN (SELECT TransactionId FROM #NwrAdjustmentFees)

DROP TABLE #Nwr622Fees
DROP TABLE #Nwr649Adjustments
DROP TABLE #NwrAdjustmentFees

--End Customization

--Begin Customization
--Get all reversal of transactions that were disbursed to the payment account or payed by others

--Remove 638 $0 transactions
DELETE FROM #DsTransactions WHERE Amount = 0 AND TransactionTypeId = 638

SELECT dt1.TransactionId 
INTO #ReversedTransactionsNotProperlyDisbursed -- SELECT *
FROM #DsTransactions dt1
LEFT JOIN #DsTransactions dt2 
ON dt1.ParentTransactionId = dt2.ParentTransactionId
AND dt1.TransactionTypeId = dt2.TransactionTypeId
AND dt1.TransactionId <> dt2.TransactionId
WHERE dt1.TransactionTypeId IN (634, 638) 
AND dt1.IsReversed = 1
AND dt2.TransactionId IS NULL

DELETE FROM #DsTransactions
WHERE TransactionId IN (SELECT TransactionId FROM #ReversedTransactionsNotProperlyDisbursed)

DROP TABLE #ReversedTransactionsNotProperlyDisbursed
--End Customization

SELECT t1.* 
INTO #DisbursementChildrenToRemove
FROM #DsTransactions t1
JOIN #DisbursementParents t2 ON t1.ParentTransactionId = t2.TransactionId
LEFT JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 2
WHERE t3.Id is null

INSERT #DisbursementChildrenToRemove
SELECT t1.* 
FROM #DsTransactions t1
WHERE t1.TransActionTypeID = 810
AND t1.Amount < 0.0

SELECT t1.* 
INTO #AdjustmentChildrenToRemove
FROM #DsTransactions t1
JOIN #AdjustmentParents t2 ON t1.ParentTransactionId = t2.TransactionId
LEFT JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 3
WHERE t3.Id is null

--SELECT TransactionId FROM #AdjustmentChildrenToRemove

SELECT t1.* 
INTO #TransferChildrenToRemove --SELECT *
FROM #DsTransactions t1
JOIN #TransferParents t2 ON t1.ParentTransactionId = t2.TransactionId
LEFT JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 4
WHERE t3.Id is null

SELECT t1.* 
INTO #NewTransferChildrenToRemove --SELECT *
FROM #DsTransactions t1
JOIN #NewTransferParents t2 ON t1.ParentTransactionId = t2.TransactionId
LEFT JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 4
WHERE t3.Id is not null


--SELECT * FROM #DsTransactions WHERE TransactionTypeID = 652
--SELECT * FROM #TransferChildrenToRemove
--Begin Customization, already been fixed in NWR (2/15/2011)
DELETE FROM #TransferChildrenToRemove
WHERE TransactionId IN (
    SELECT t1.TransactionId 
    FROM #DsTransactions t1
    INNER JOIN #DsTransactions t2 ON t1.ParentTransactionId = t2.TransactionId
    WHERE t2.TransactionTypeId = 652
    AND t1.TransactionTypeId = 652
    AND t2.Amount = 0
    AND t1.DisbursementAccountId != t1.AccountId
)

--SELECT * FROM #TransferChildrenToRemove

UPDATE #DsTransactions
SET AccountId = t1.DisbursementAccountId
FROM #DsTransactions t1
INNER JOIN (
    SELECT * FROM #DsTransactions
    WHERE TransactionTypeId = 652
    AND Amount = 0) t2
ON t1.ParentTransactionId = t2.TransactionId
WHERE t1.TransactionTypeID = 652
AND t1.DisbursementAccountId != t1.AccountId


--------------------------------------------------------------------------
-- Handle 800 Seriers Transactions
--------------------------------------------------------------------------
--Add the trans back in where DisbursementAccountId = AccountId
DELETE FROM #NewTransferChildrenToRemove -- SELECT * FROM #NewTransferChildrenToRemove 
WHERE TransactionId IN (
    SELECT t1.TransactionId 
    FROM #DsTransactions t1
    INNER JOIN #DsTransactions t2 ON t1.ParentTransactionId = t2.TransactionId
    WHERE t2.TransactionTypeId IN (800,801,802,803,804,805,806,807,808,809)
    AND t1.TransactionTypeId = t2.TransactionTypeId 
)
	
--Change the AccountID to assign the trans to the account that owns
UPDATE #DsTransactions SET 
	AccountId = DisbursementAccountId
WHERE TransactionId IN (
	SELECT t1.TransactionId	
	FROM #DsTransactions t1
	INNER JOIN #DsTransactions t2 ON t1.ParentTransactionId = t2.TransactionId
	WHERE t2.TransactionTypeId IN (800,801,802,803,804,805,806,807,808,809)
	AND t1.TransactionTypeId = t2.TransactionTypeId 
	AND t1.DisbursementAccountId != t1.AccountId
	)
--------------------------------------------------------------------------

--End of Customization

--SELECT * FROM #DsTransactions WHERE TransactionTypeID = 652

--Place all children to remove in one TABLE
SELECT *
INTO #ChildrenToRemove
FROM #PaymentChildrenToRemove
UNION SELECT * FROM #DisbursementChildrenToRemove
UNION SELECT * FROM #AdjustmentChildrenToRemove
UNION SELECT * FROM #TransferChildrenToRemove
UNION SELECT * FROM #NewTransferChildrenToRemove


----------------------------------------------------------------------------------------------------------------------------------------------
--Update sign on amount by context
----------------------------------------------------------------------------------------------------------------------------------------------

UPDATE #DsTransactions
SET Amount = t1.Amount * -1 -- SELECT *
FROM #DsTransactions t1
INNER JOIN #PaymentParents t2 ON t1.ParentTransactionId = t2.TransactionId
OR t1.TransactionId = t2.TransactionId
INNER JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 1
WHERE t3.ReverseSign = 1

UPDATE #DsTransactions
SET Amount = t1.Amount * -1 -- SELECT *
FROM #DsTransactions t1
INNER JOIN #DisbursementParents t2 ON t1.ParentTransactionId = t2.TransactionId
OR t1.TransactionId = t2.TransactionId
INNER JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 2
WHERE t3.ReverseSign = 1

UPDATE #DsTransactions
SET Amount = t1.Amount * -1 -- SELECT *
FROM #DsTransactions t1
INNER JOIN #AdjustmentParents t2 ON t1.ParentTransactionId = t2.TransactionId
OR t1.TransactionId = t2.TransactionId
INNER JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 3
WHERE t3.ReverseSign = 1

UPDATE #DsTransactions
SET Amount = t1.Amount * -1 -- SELECT *
FROM #DsTransactions t1
INNER JOIN #TransferParents t2 ON t1.ParentTransactionId = t2.TransactionId
OR t1.TransactionId = t2.TransactionId
INNER JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 4
WHERE t3.ReverseSign = 1

UPDATE #DsTransactions
SET Amount = t1.Amount * -1 -- SELECT *
FROM #DsTransactions t1
INNER JOIN #NewTransferParents t2 ON t1.ParentTransactionId = t2.TransactionId
OR t1.TransactionId = t2.TransactionId
INNER JOIN TransactionContextTransactionTypes t3 WITH (NOLOCK) ON t1.TransactionTypeId = t3.TransactionTypeId AND t3.TransactionContextId = 4
WHERE t3.ReverseSign = 1

UPDATE #DsTransactions
SET Amount = t1.Amount * -1
FROM #DsTransactions t1
WHERE TransactionId in (
	SELECT t1.TransactionId 
	FROM #DsTransactions t1
	INNER JOIN #FeeReallocationParents t2 ON t1.ParentTransactionId = t2.ParentTransactionId
	WHERE t1.TransactionTypeId = 620
	AND t1.DisbursementAccountId = t1.AccountId
	AND t2.Amount = (-1 * t1.Amount)
	)


						
--Change sign of a 622 used as a transfer
UPDATE #DsTransactions
SET Amount = Amount * -1 -- SELECT *
WHERE TransactionTypeId = 622
AND AccountId <> DisbursementAccountId

DROP TABLE #PaymentParents
DROP TABLE #DisbursementParents
DROP TABLE #AdjustmentParents
DROP TABLE #TransferParents
DROP TABLE #NewTransferParents
DROP TABLE #FeeReallocationParents
DROP TABLE #PaymentChildrenToRemove
DROP TABLE #DisbursementChildrenToRemove
DROP TABLE #AdjustmentChildrenToRemove
DROP TABLE #TransferChildrenToRemove
DROP TABLE #NewTransferChildrenToRemove

-------------------------------------------------------------------------------------------------------------------------------------------------------
--Filter AND adjust parentIds ON transactions before inserting INTO DebtManager 
-------------------------------------------------------------------------------------------------------------------------------------------------------

--SELECT TransactionId FROM #ChildrenToRemove

--Delete children FROM #DsTransactions
DELETE FROM #DsTransactions
WHERE TransactionGuid in (SELECT TransactionGuid FROM #ChildrenToRemove)

--SELECT * FROM #DsTransactions

DROP TABLE #ChildrenToRemove

--SELECT * FROM #ParentsToRemove

--Remove $0 transactions
DELETE FROM #DsTransactions WHERE Amount = 0

--Assign new parent to children that were orphaned AND remove parents

Declare @i INT
Declare @TransactionId INT
Declare @NewParentId INT
Declare @rows INT

SET @i = 1
SET @rows = (SELECT count(*) FROM #ParentsToRemove)

if @rows > 0
	while (@i <= @rows)
	begin
		SET @TransactionId = (SELECT TransactionId FROM #ParentsToRemove
								WHERE Row = @i)
		
		SET @NewParentId = (SELECT TOP 1 TransactionId FROM #DsTransactions
								WHERE ParentTransactionId = @TransactionId)
		
		--CREATE new parent FROM one of the children of the parent being removed
		UPDATE #DsTransactions
		SET ParentTransactionId = null 
		WHERE TransactionId = (SELECT TOP 1 TransactionId FROM #DsTransactions
																WHERE ParentTransactionId = @TransactionId)
		--related to the parent being removed, assign the rest of the children to the newly made parent		
		UPDATE #DsTransactions
		SET ParentTransactionId = @NewParentId
		WHERE ParentTransactionId = @TransactionId
		
		--remove the parent
		DELETE FROM #DsTransactions
		WHERE TransactionId = @TransactionId
		
		--remove the parent here also
		DELETE FROM #ParentsToRemove
		WHERE TransactionId = @TransactionId
		
		SET @i = @i + 1
	end		

DROP TABLE #ParentsToRemove


--Build families by transaction guid
SELECT t1.TransactionGuid, COALESCE (t2.TransactionGuid, t3.LedgerTransactionUid) 'ParentGuid'
INTO #Families
FROM #DsTransactions t1
LEFT JOIN #DsTransactions t2 ON t1.ParentTransactionId = t2.TransactionId
LEFT JOIN LedgerTransactions t3 ON t1.ParentTransactionId = t3.SequenceNumber

--Getting settlement payee names
--so that settlements will show the disbursement payee, instead of the consumer, disbursement account id

SELECT t.TransactionGUID, cdi.PayeeName
INTO #SettlementPayeeNames -- SELECT * 
FROM #DsTransactions t
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Credits c WITH(NOLOCK) ON t.ParentTransactionID = c.TransactionID
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.CreditAllocationInstructions cai WITH(NOLOCK) ON c.CreditID = cai.CreditID
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.CreditDisbursementInstructions cdi WITH(NOLOCK) ON cai.CreditAllocationInstructionID = cdi.CreditAllocationInstructionID
WHERE t.TransactionTypeId = 661

-- 652 : Has the correct Payee Name.
-- 654 : The one we do not have the correct payee name
--Getting 652 disbursement account names for 654 transactions
--so that the 654 transfer credit can show that it is going to a different account; otherwise, it will show going to the consumer account.
-- Start Customization
SELECT t654.TransactionGuid, c.Name
INTO #TransferCreditPayeeNames -- SELECT t652.*, t654.* -- SELECT a.AccountId, a.ContactId, c.ContactId, c.Name
FROM #DsTransactions t654
INNER JOIN #DsTransactions t652 ON t654.ParentTransactionId = t652.ParentTransactionId
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts a WITH(NOLOCK) ON t652.DisbursementAccountId = a.AccountId
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Contacts c WITH(NOLOCK) ON a.ContactId = c.ContactId
WHERE t654.TransactionTypeId = 654 AND t652.TransactionTypeId = 652
-- End Customization

--Getting the debit disbursement names from the allocation instructions, except for 654 transactions
--because these names are different than the disbursement account used in the transaction

SELECT Transactions.TransactionGuid, Contacts.Name
INTO #DebitAllocationNames
FROM #DsTransactions Transactions
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Debits WITH(NOLOCK) ON  Transactions.ReceiptId = Debits.ReceiptId
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.DebitAllocationInstructions WITH(NOLOCK) 
	ON Debits.DebitId = DebitAllocationInstructions.DebitId
	AND DebitAllocationInstructions.AllocationTypeId = Transactions.AllocationTypeId
	AND DebitAllocationInstructions.Amount = Transactions.Amount AND Transactions.IsReversed = 0
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts AccountControlGroup WITH(NOLOCK) ON Debits.AccountId = AccountControlGroup.AccountId -- for controlgroup
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.AllocationTypeControlGroups AllocationControl WITH(NOLOCK)
	ON DebitAllocationInstructions.AllocationTypeId = AllocationControl.AllocationTypeId 
	AND AllocationControl.ControlGroupId = AccountControlGroup.ControlGroupId
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.AllocationDisbursementAccounts WITH(NOLOCK)
	ON AllocationControl.AllocationTypeControlGroupId = AllocationDisbursementAccounts.AllocationTypeControlGroupId 
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts WITH(NOLOCK) ON AllocationDisbursementAccounts.AccountId = Accounts.AccountId
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Contacts WITH(NOLOCK) ON Accounts.ContactId = Contacts.ContactId
WHERE Transactions.TransactionTypeId <> 654

--Joining PayeeNames into one table
--so that the names can be used instead of the transaction disbursement account id

SELECT *
INTO #OtherPayeeNames
FROM #SettlementPayeeNames

UNION

SELECT *
FROM #TransferCreditPayeeNames

UNION

SELECT *
FROM #DebitAllocationNames

DROP TABLE #TransferCreditPayeeNames
DROP TABLE #SettlementPayeeNames
DROP TABLE #DebitAllocationNames

--SELECT * FROM #DsTransactions ORDER BY TransactionId

--------------------------------------------------------------------------------------------------------------------------------
--Preparing DebtManager LedgerTransactions to restore balance
--------------------------------------------------------------------------------------------------------------------------------
DECLARE @RemainingBalance money
SET @RemainingBalance = 0
--Load transactions FROM #DsTransactions, WITH DebtManager corresponding fields
SELECT
DmTranTypes.TransactionTypeId
,'TransactionDate' = dbo.fnDateTrunc(case when Receipts.EffectiveDate is NOT null then Receipts.EffectiveDate else DsTrans.CreationDateTime end)
,DsTrans.TransactionGuid 'LedgerTransactionUid'
,COALESCE(OtherPayees.PayeeName, Contacts.Name) 'PayeeName'
,DsTrans.Amount
,DmTranTypes.Name 'Description'
,@RemainingBalance 'RemainingBalance'
,null 'ParentId'
,DsTrans.IsClearedForGoodFunds 'HasCleared'
,DsTrans.TransactionId 'SequenceNumber'
,Accts.DmAccountId 'AccountId'
INTO #TransactionsToRestore --SELECT DsTrans.*, Accts.* --SELECT TOP 1 * FROM LedgerTransactions
FROM #AccountsToRestore Accts
INNER JOIN #DsTransactions DsTrans ON DsTrans.AccountId = Accts.DsAccountId OR DsTrans.DisbursementAccountId = Accts.DsAccountId
INNER JOIN TransactionTypes DmTranTypes WITH (NOLOCK) ON DsTrans.TransactionTypeGuid = DmTranTypes.TransactionTypeGuid--TransactionTypId
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts AcctContacts ON DsTrans.DisbursementAccountId = AcctContacts.AccountId
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Contacts Contacts WITH (NOLOCK) ON AcctContacts.ContactId = Contacts.ContactId --payeeName
LEFT JOIN DebtSettlementLink.DebtSettlement.dbo.Receipts Receipts WITH (NOLOCK) ON DsTrans.ReceiptId = Receipts.ReceiptId --TransactionDate
LEFT JOIN #OtherPayeeNames OtherPayees ON DsTrans.TransactionGuid = OtherPayees.TransactionGuid

DROP TABLE #DsTransactions
DROP TABLE #OtherPayeeNames

--------------------------------------------------------------------------------------------------------------------------------
--Validating DebtManager LedgerTransactions
--------------------------------------------------------------------------------------------------------------------------------

--Update ParentIds
--in case Parents have been removed

UPDATE #TransactionsToRestore SET 
	ParentId = t1.Id 
FROM (
	SELECT t2.Id, t3.TransactionGuid 
	FROM LedgerTransactions t2 
	JOIN #Families t3 ON t2.LedgerTransactionUid = t3.ParentGuid
	) AS t1
WHERE LedgerTransactionUid = t1.TransactionGuid

--Creating a table of the remaining balances by AccountId
--for inserting into the #TransactionsToRestore table

CREATE TABLE #LedgerTransactionOrder (
	Row int IDENTITY (1,1),
	LedgerTransactionUid uniqueIdentifier,
	Amount money,
	TransactionDate datetime,
	SequenceNumber int,
	AccountId int,
	HasCleared bit)

	
INSERT INTO #LedgerTransactionOrder
SELECT LedgerTransactionUid, Amount, TransactionDate, SequenceNumber, AccountId, HasCleared
FROM #TransactionsToRestore
ORDER BY AccountId, TransactionDate, SequenceNumber

SELECT trans.Row, trans.TransactionDate, trans.SequenceNumber, trans.LedgerTransactionUid 'TransactionUid', trans.Amount, 
SUM(rb.Amount) 'RemainingBalance', trans.AccountId 'RunningBalanceAccountId'
INTO #RunningBalances  --SELECT trans.TransactionDate, trans.SequenceNumber, trans.LedgerTransactionUid 'TransactionUid', trans.Amount, SUM(rb.Amount) 'RemainingBalance', trans.AccountId 'RunningBalanceAccountId'
FROM #LedgerTransactionOrder trans
INNER JOIN #LedgerTransactionOrder rb ON trans.AccountId = rb.AccountId
WHERE rb.Row <= trans.Row
AND rb.HasCleared = 1
GROUP BY trans.AccountId, trans.Row, trans.TransactionDate, trans.SequenceNumber, trans.LedgerTransactionUid, trans.Amount
ORDER BY trans.AccountId, trans.Row, trans.TransactionDate, trans.SequenceNumber

UPDATE #TransactionsToRestore
	SET RemainingBalance = rb.RemainingBalance
FROM #RunningBalances rb
WHERE LedgerTransactionUid = rb.TransactionUid


--Update the DmReserveBalance from the last account transaction remaining balance
--for checking to see if the reserve balances are now in sync
UPDATE #AccountsToRestore
	SET DmReserveBalance = rb.RemainingBalance
FROM (
	SELECT MAX(Row) 'RowNumber', RunningBalanceAccountId
	FROM #RunningBalances
	GROUP BY RunningBalanceAccountId
	) sn
INNER JOIN #RunningBalances rb ON sn.RowNumber = rb.Row
WHERE DmAccountId = rb.RunningBalanceAccountId

--SELECT * FROM #AccountsToRestore
--SELECT * FROM #RunningBalances
DROP TABLE #LedgerTransactionOrder
DROP TABLE #RunningBalances

--Create a table of out-of-sync accounts
--so the accounts can have a 'Balance Forward' transaction and update of AccountCurrentReserveBalance

SELECT * 
INTO #AccountsOutOfSync -- SELECT * 
FROM #AccountsToRestore
WHERE DmReserveBalance <> AdjustedReserveBalance

--SELECT * FROM #AccountsOutOfSync

--Remove accounts from the #AccountsToRestore which reserve balances are not in sync
--So the table contains only accounts being restore


-----------------------------------------------------------------------------------
-- ### Create AuditHistory for Skipped AccountsToRestore ###
-----------------------------------------------------------------------------------
INSERT LedgerTransactions_AuditHistory(AccountID, AuditStatusId, RunningBalanceCalculation, AdjustedReserveBalance, SessionId) 
	SELECT DmAccountID, 3, DmReserveBalance, AdjustedReserveBalance, (SELECT SessionId FROM #AuditSession)
	FROM #AccountsToRestore
	WHERE DmReserveBalance <> AdjustedReserveBalance

INSERT LedgerTransactions_InvalidTransactionList(TransactionTypeID, TransactionDate, LedgerTransactionUID, PayeeName, Amount, Description, RemainingBalance, ParentID, HasCleared, SequenceNumber, AccountID, SessionId)
	SELECT TransactionTypeId, TransactionDate, LedgerTransactionUid, PayeeName, Amount, Description, RemainingBalance, ParentId, HasCleared, SequenceNumber, AccountId, (SELECT SessionId FROM #AuditSession)
	FROM #TransactionsToRestore
	WHERE AccountId IN (SELECT DmAccountId FROM #AccountsOutOfSync)
	ORDER BY AccountId, TransactionDate, SequenceNumber

PRINT CAST(@@RowCount AS varchar(10)) + ' transactions logged for skipped accounts'



DELETE
FROM #AccountsToRestore -- SELECT * FROM #AccountsToRestore
WHERE DmReserveBalance <> AdjustedReserveBalance

--Remove transactions from #TransactionsToRestore on accounts in the #AccountsOutOfSync table
--so these transactions causing an out-of-sync don't get inserted into the LedgerTransactions table
DELETE
FROM #TransactionsToRestore -- SELECT * FROM #TransactionsToRestore
WHERE AccountId IN (SELECT DmAccountId FROM #AccountsOutOfSync)


--Remove any accounts that already have a Balance Forward and the reserve balance is in sync
--so those accounts don't get purged and re-updated with a 'Balance Forward' transaction
DELETE
FROM #AccountsOutOfSync -- SELECT * FROM #AccountsOutOfSync
WHERE DmAccountId IN (
	Select Acct.AccountId 
	FROM Account Acct
	INNER JOIN LedgerTransactions LedgeTran ON Acct.AccountId = LedgeTran.AccountId 
	WHERE Description = 'Balance Forward'
	AND AccountCurrentReserveBalance = AdjustedReserveBalance
	)

DECLARE @num int
SET @num = (SELECT COUNT(*) FROM #AccountsToRestore WHERE DmAccountId IN (SELECT * FROM #BalanceForwardAccounts))
PRINT CAST(@num AS varchar(5)) + ' Balance-Forward accounts being restored'

SET @num = (SELECT COUNT(*) FROM #AccountsOutOfSync WHERE DmAccountId NOT IN (SELECT * FROM #BalanceForwardAccounts))
PRINT CAST(@num AS varchar(5)) + ' out-of-sync accounts getting a Balance-Forward transaction'

SET @num = (SELECT COUNT(*) FROM #AccountsToRestore)
PRINT CAST(@num AS varchar(5)) + ' total accounts being restored'






--------------------------------------------------------------------------------------------------------------------------------
--Restoring DebtManager LedgerTransactions
--------------------------------------------------------------------------------------------------------------------------------
BEGIN TRAN

--Delete Balance Forward transactions that currently exist for #AccountsToRestore
--so new ledger transactons can be inserted

DELETE -- SELECT *
FROM LedgerTransactions 
WHERE Description = 'Balance Forward'
AND AccountId in (SELECT DmAccountId FROM #AccountsToRestore)

--Get LedgerTransactionIds that exist in LedgerTransactions but not in #TransactionsToRestore
--so these ids can be removed from the ReserveDisburment and Debit tables ResultingTransactionId
--and consecutively deleteing the LedgerTransaction with that Id

SELECT Id
INTO #PossibleResultingTransactionIds -- SELECT Id
FROM LedgerTransactions
WHERE LedgerTransactionUid NOT IN (SELECT LedgerTransactionUid FROM #TransactionsToRestore)
AND AccountId IN (SELECT DmAccountId FROM #AccountsToRestore)

--Update LedgerTransaction references to Null in ReserveDisbursements
--because a foreign key constraint exists in the table not allowing a delete of a LedgerTransaction

UPDATE ReserveDisbursements
SET ResultingTransactionId = NULL -- SELECT * FROM ReserveDisbursements
WHERE ResultingTransactionId IN (SELECT Id FROM #PossibleResultingTransactionIds)

--Update LedgerTransaction references to Null in Debit
--because a foreign key constraint exists in the table not allowing a delete of a LedgerTransaction

UPDATE Debit
SET ResultingTransactionID = NULL -- SELECT * FROM Debit 
WHERE ResultingTransactionID IN (SELECT Id FROM #PossibleResultingTransactionIds)

--Insert transactions that are being removed from LedgerTransactionsTable
INSERT INTO LedgerTransactions_Corrections
	SELECT *, 1 'WasRemoved', GETDATE(), (SELECT SessionId FROM #AuditSession)
	FROM LedgerTransactions
	WHERE LedgerTransactionUid NOT IN (SELECT LedgerTransactionUid FROM #TransactionsToRestore)
	AND AccountId IN (SELECT DmAccountId FROM #AccountsToRestore)

--Delete transactions not in the #TransactionsToRestore
--to eliminate transactions that cause an imbalance
DELETE -- SELECT *
FROM LedgerTransactions
WHERE LedgerTransactionUid NOT IN (SELECT LedgerTransactionUid FROM #TransactionsToRestore)
AND AccountId IN (SELECT DmAccountId FROM #AccountsToRestore)

--Delete from #TransactionsToRestore those transactions that already exist in LedgerTransactions
DELETE -- SELECT *
FROM #TransactionsToRestore
WHERE LedgerTransactionUid IN (SELECT LedgerTransactionUid FROM LedgerTransactions)

--Insert, into a table, transactions that are being added to LedgerTransactions

INSERT INTO LedgerTransactions_Corrections 
	SELECT null, *, 0, GETDATE(), (SELECT SessionId FROM #AuditSession) 
	FROM #TransactionsToRestore

--Insert into LedgerTransactions transactions from #TransactionsToRestore
--so the account LedgerTransactions are restored and can be balanced

INSERT INTO LedgerTransactions SELECT * FROM #TransactionsToRestore

--Update ParentIds

UPDATE LedgerTransactions
SET ParentId = t1.Id -- SELECT *
FROM (SELECT t2.Id, t3.TransactionGuid FROM LedgerTransactions t2 
		JOIN #Families t3 ON t2.LedgerTransactionUid = t3.ParentGuid) AS t1
WHERE LedgerTransactionUid = t1.TransactionGuid

--Creating a table of the remaining balances by AccountId
--for inserting into the #TransactionsToRestore table

CREATE TABLE #LedgerTransactionOrderUpdate (
	Row int IDENTITY (1,1),
	LedgerTransactionUid uniqueIdentifier,
	Amount money,
	TransactionDate datetime,
	SequenceNumber int,
	AccountId int,
	HasCleared bit)

	
INSERT INTO #LedgerTransactionOrderUpdate
SELECT LedgerTransactionUid, Amount, TransactionDate, SequenceNumber, AccountId, HasCleared
FROM LedgerTransactions
INNER JOIN #AccountsToRestore ON DmAccountId = AccountId
ORDER BY AccountId, TransactionDate, SequenceNumber

SELECT trans.Row, trans.TransactionDate, trans.SequenceNumber, trans.LedgerTransactionUid 'TransactionUid', trans.Amount, 
SUM(rb.Amount) 'RemainingBalance', trans.AccountId 'RunningBalanceAccountId'
INTO #ActualRunningBalances  --SELECT trans.TransactionDate, trans.SequenceNumber, trans.LedgerTransactionUid 'TransactionUid', trans.Amount, SUM(rb.Amount) 'RemainingBalance', trans.AccountId 'RunningBalanceAccountId'
FROM #LedgerTransactionOrderUpdate trans
INNER JOIN #LedgerTransactionOrderUpdate rb ON trans.AccountId = rb.AccountId
WHERE rb.Row <= trans.Row
AND rb.HasCleared = 1
GROUP BY trans.AccountId, trans.Row, trans.TransactionDate, trans.SequenceNumber, trans.LedgerTransactionUid, trans.Amount
ORDER BY trans.AccountId, trans.Row, trans.TransactionDate, trans.SequenceNumber

UPDATE LedgerTransactions
SET RemainingBalance = rb.RemainingBalance -- SELECT *
FROM #ActualRunningBalances rb
INNER JOIN #AccountsToRestore atr ON rb.RunningBalanceAccountId = atr.DmAccountId
WHERE LedgerTransactionUid = rb.TransactionUid

--Update AccountCurrentReserveBalance in Account
--so the balance will be in sync with the DebtSettlement Accounts ReserveBalance that is adjusted with the
--account receivable balance

UPDATE Account
SET AccountCurrentReserveBalance = rb.RemainingBalance
FROM (SELECT MAX(Row) 'RowNumber', RunningBalanceAccountId
		FROM #ActualRunningBalances
		GROUP BY RunningBalanceAccountId) sn
INNER JOIN #ActualRunningBalances rb ON sn.RowNumber = rb.Row
INNER JOIN #AccountsToRestore rtb ON rtb.DmAccountId = rb.RunningBalanceAccountId
WHERE AccountId = rb.RunningBalanceAccountId

DROP TABLE #LedgerTransactionOrderUpdate

--Update #AccountsToRestore DmAccountBalance

UPDATE #AccountsToRestore
SET DmReserveBalance = rb.RemainingBalance --SELECT *
FROM (SELECT MAX(Row) 'RowNumber', RunningBalanceAccountId
		FROM #ActualRunningBalances
		GROUP BY RunningBalanceAccountId) sn
INNER JOIN #ActualRunningBalances rb ON sn.RowNumber = rb.Row
INNER JOIN #AccountsToRestore rtb ON rtb.DmAccountId = rb.RunningBalanceAccountId
WHERE DmAccountId = rb.RunningBalanceAccountId

--SELECT * FROM #ActualRunningBalances
--SELECT * FROM #AccountsToRestore

--Insert #AccountsToRestore into #AccountsOutOfSync that are still not in balance

INSERT INTO #AccountsOutOfSync
SELECT * FROM #AccountsToRestore
WHERE DmReserveBalance <> AdjustedReserveBalance
DROP TABLE #ActualRunningBalances
DROP TABLE #TransactionsToRestore
DROP TABLE #Families
DROP TABLE #PossibleResultingTransactionIds



-----------------------------------------------------------------------------------
-- ### Create AuditHistory Records ###
-----------------------------------------------------------------------------------
INSERT LedgerTransactions_AuditHistory(AccountID, AuditStatusId, RunningBalanceCalculation, AdjustedReserveBalance, SessionId) 
	SELECT DmAccountID, 2, DmReserveBalance, AdjustedReserveBalance, (SELECT SessionId FROM #AuditSession)
	FROM #AccountsToRestore
	WHERE DmAccountID NOT IN (
		SELECT DmAccountID FROM #AccountsOutOfSync
		)

INSERT LedgerTransactions_AuditHistory(AccountID, AuditStatusId, RunningBalanceCalculation, AdjustedReserveBalance, SessionId) 
	SELECT DmAccountID, 1, DmReserveBalance, AdjustedReserveBalance, (SELECT SessionId FROM #AuditSession)
	FROM #AccountsOutOfSync

DELETE FROM LedgerTransactions_AuditHistory
WHERE ID IN (
	SELECT ID FROM LedgerTransactions_AuditHistory
	WHERE SessionId IN (
		SELECT SessionId FROM #AuditSession
		)
	AND AccountId IN (
		SELECT AccountId FROM LedgerTransactions_AuditHistory
		WHERE SessionId IN (
			SELECT SessionId FROM #AuditSession
			)
		AND AuditStatusId != 3
		)
	AND AuditStatusId = 3
	)
PRINT CAST(@@RowCount AS varchar(10)) + ' duplicate rows removed from AuditHistory'

-----------------------------------------------------------------------------------



--------------------------------------------------------------------------------------------------------------------------------
--Purging transactions and creating a Balance-Forward transaction on accounts that couldn't be synced
--------------------------------------------------------------------------------------------------------------------------------
--Get LedgerTransactionId from LedgerTransactions that need to be removed
--so those with corresponding ResultingTransactionId can be identified

SELECT Id
INTO #LedgerTransactionsToRemove -- SELECT *
FROM LedgerTransactions WHERE AccountId IN (SELECT DmAccountId FROM #AccountsOutOfSync)

--Update LedgerTransaction references to Null in ReserveDisbursements
--because a foreign key constraint exists in the table not allowing a delete of a transaction

UPDATE ReserveDisbursements
SET ResultingTransactionID = NULL -- SELECT * FROM ReserveDisbursements
WHERE ResultingTransactionID IN (SELECT Id FROM #LedgerTransactionsToRemove)

-- Update Debit using Transaction IDs and ParentID FROM #LedgerTransactionsToRemove

UPDATE Debit
SET ResultingTransactionID = NULL -- SELECT * FROM Debit
WHERE ResultingTransactionID IN (SELECT Id FROM #LedgerTransactionsToRemove)

--Store transactions purged into a table before removing

INSERT INTO LedgerTransactions_Purged
	SELECT *, (SELECT SessionId FROM #AuditSession) 
	FROM LedgerTransactions WHERE Id IN (SELECT * FROM #LedgerTransactionsToRemove)

--Purge current transacions of accounts still not in sync
--so consummers can not see an out-of-balance ledger

DELETE -- SELECT *
FROM LedgerTransactions WHERE Id IN (SELECT * FROM #LedgerTransactionsToRemove)

--Insert 600 trans into DebtManager with NSS_ReserveBalance for each NWRAccountID in #AccountsOutOfSync
--so consumers can see the balance on their account

DECLARE @TransType INT
DECLARE @PayeeName VARCHAR(10)
DECLARE @Date DATETIME
DECLARE @HasCleared BIT
DECLARE @Description VARCHAR(25)

SET @TransType = 600
SET @PayeeName = 'CONVERSION'
SET @Date = dbo.fnDateTrunc(GETDATE())
SET @HasCleared = 1
SET @Description = 'Balance Forward'

INSERT INTO LedgerTransactions (TransactionTypeID, TransactionDate, LedgerTransactionUID, PayeeName, Amount, HasCleared, RemainingBalance, AccountID, Description)
	SELECT @TransType, @Date, NEWID(), @PayeeName, AdjustedReserveBalance, @HasCleared, AdjustedReserveBalance, DmAccountID, @Description
	FROM #AccountsOutOfSync

--Update accounts table with reserve balance FROM #AccountsOutOfSync
UPDATE Account
SET AccountCurrentReserveBalance = AdjustedReserveBalance 
FROM #AccountsOutOfSync
WHERE AccountID = DmAccountID


UPDATE LedgerTransactions_AuditSession SET 
	SessionComplete = GetDate() 
WHERE SessionId IN (
	SELECT SessionId FROM #AuditSession
	)


--SELECT * FROM #AccountsOutOfSync

DROP TABLE #AccountsToRestore
DROP TABLE #AccountsOutOfSync
DROP TABLE #LedgerTransactionsToRemove
DROP TABLE #BalanceForwardAccounts


COMMIT TRAN
--ROLLBACK TRAN


SET NOCOUNT OFF;


SELECT *, ProcessSeconds = DATEDIFF(second, SessionDate, SessionComplete) 
FROM LedgerTransactions_AuditSession 
WHERE SessionId IN (SELECT SessionId FROM #AuditSession)

SELECT SessionId, AuditStatus = T2.Description, [Count] = COUNT(ID)
FROM LedgerTransactions_AuditHistory T1
JOIN LedgerTransactions_AuditStatus T2 ON T2.AuditStatusId = T1.AuditStatusId
WHERE SessionId IN (SELECT SessionId FROM #AuditSession)
GROUP BY SessionId, T2.Description ORDER BY SessionId


SELECT SessionId, InvalidTransactionList_Count = COUNT(ID)
FROM LedgerTransactions_InvalidTransactionList
WHERE SessionId IN (SELECT SessionId FROM #AuditSession)
GROUP BY SessionId ORDER BY SessionId



DROP TABLE #AuditSession



/*
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
-- Query logging tables
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------

DROP TABLE #AuditSession
SELECT SessionId = MAX(SessionId) INTO #AuditSession FROM LedgerTransactions_AuditSession
--SELECT SessionId = 24 into #AuditSession

SELECT * 
FROM LedgerTransactions_AuditSession 
WHERE SessionId IN (SELECT SessionId FROM #AuditSession)

SELECT ID, SessionId, AccountID, RunningBalanceCalculation, AdjustedReserveBalance, T1.AuditStatusId, AuditStatus = T2.Description
FROM LedgerTransactions_AuditHistory T1
JOIN LedgerTransactions_AuditStatus T2 ON T2.AuditStatusId = T1.AuditStatusId
WHERE SessionId IN (SELECT SessionId FROM #AuditSession)
ORDER BY T1.AuditStatusId, ID 


SELECT Id, TransactionTypeID, TransactionDate, LedgerTransactionUID, PayeeName, Amount, Description, RemainingBalance, ParentID, HasCleared, SequenceNumber, AccountID, SessionId
FROM LedgerTransactions_InvalidTransactionList
WHERE SessionId IN (
	SELECT SessionId FROM #AuditSession
	)


SELECT *
FROM LedgerTransactions_Corrections WHERE SessionId IN (
	SELECT SessionId FROM #AuditSession
	)

SELECT *
FROM LedgerTransactions_Purged WHERE SessionId IN (
	SELECT SessionId FROM #AuditSession
	)



--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
-- Review Ledger & NSS History
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------

DECLARE @AccountID int, @ShowCleared int
SET @ShowCleared = 1
SET @AccountID =  284260 




IF ( object_id('tempdb..#AccountsToRestore') IS NOT NULL ) DROP TABLE #AccountsToRestore
SELECT DmAccounts.AccountUid, DmAccounts.AccountId 'DmAccountId', DmAccounts.AccountCurrentReserveBalance 'DmReserveBalance', DsAccounts.AccountId 'DsAccountId', DsAccounts.ReserveBalance 'DsReserveBalance', AdjustedReserveBalance = DsAccounts.ReserveBalance - ISNULL(Advances.AdvanceBalance, 0), DsAccounts.ContactId 'DsContactId'
INTO #AccountsToRestore
FROM Account DmAccounts INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts DsAccounts ON DmAccounts.AccountUid = DsAccounts.AccountGuid LEFT JOIN DebtSettlementLink.DebtSettlement.dbo.vCorporateAdvancesByAccount Advances ON DsAccounts.AccountId = Advances.AccountId
WHERE DmAccounts.AccountID = @AccountID


PRINT REPLICATE('=',80)
PRINT '==  AccountsToRestore'; 
PRINT REPLICATE('=',80)

SELECT *
FROM #AccountsToRestore


PRINT REPLICATE('=',80)
PRINT '==  LedgerTransactions_AuditHistory'; 
PRINT REPLICATE('=',80)

	SELECT ID, SessionId, AccountID, RunningBalanceCalculation, AdjustedReserveBalance, BalanceDiff = AdjustedReserveBalance - RunningBalanceCalculation, T1.AuditStatusId, AuditStatus = T2.Description
	FROM LedgerTransactions_AuditHistory T1
	JOIN LedgerTransactions_AuditStatus T2 ON T2.AuditStatusId = T1.AuditStatusId
	WHERE SessionId IN (
		SELECT MAX(SessionId) FROM LedgerTransactions_AuditSession 
		)
	AND AccountID = @AccountID



PRINT REPLICATE('=',80)
PRINT '==  LedgerTransactions_InvalidTransactionList'
PRINT REPLICATE('=',80)

	SELECT TransactionId = T1.SequenceNumber, T1.TransactionTypeID, T1.TransactionDate, T1.Description, T1.Amount, T1.RemainingBalance, T1.ParentID, T1.HasCleared, T1.Id, NwrLedgerTransaction = CASE WHEN T2.Id IS NULL THEN '' ELSE 'X' END
	FROM LedgerTransactions_InvalidTransactionList T1
	LEFT JOIN LedgerTransactions T2 ON T2.TransactionDate = T1.TransactionDate AND T2.Amount = T1.Amount AND ISNULL(T2.SequenceNumber,0) = ISNULL(T1.SequenceNumber,0)
	WHERE SessionId IN (
		SELECT MAX(SessionId) FROM LedgerTransactions_AuditSession 
		)
	AND T1.AccountID = @AccountID
	AND (T1.HasCleared != 0 OR @ShowCleared > 0)
	ORDER BY T1.AccountId, T1.TransactionDate, T1.SequenceNumber

PRINT REPLICATE('=',80)
PRINT '==  LedgerTransactions'
PRINT REPLICATE('=',80)

	SELECT Id, T1.TransactionTypeID, T1.TransactionDate, T1.Description, T1.Amount, T1.RemainingBalance, T2.AccountCurrentReserveBalance, T1.HasCleared
	FROM LedgerTransactions T1
	JOIN Account T2 ON T2.AccountID = T1.AccountID
	WHERE T1.AccountID  = @AccountID
	AND (T1.HasCleared != 0 OR @ShowCleared > 0)
	ORDER BY T1.AccountID, TransactionDate, SequenceNumber


PRINT REPLICATE('=',80)
PRINT '==  NSS Transactions'
PRINT REPLICATE('=',80)

	SELECT TransactionId, ParentTransactionId, AccountId, DisbursementAccountId, Trans.TransactionTypeId, TransTypes.Name, Amount, CreationDateTime, IsReallocated, IsClearedForGoodFunds, IsReversed, ReceiptId, AllocationTypeId
	FROM (
		SELECT TransactionId, ParentTransactionId, TransactionGuid, AccountId, DisbursementAccountId, ReceiptId, TransactionTypeId, Amount, IsReallocated, IsClearedForGoodFunds, IsReversed, TransactionTypeGuid, AllocationTypeId, CreationDateTime, LastEditDateTime
		FROM DebtSettlementLink.DebtSettlement.dbo.VTransactionsLedgerView Trans WITH (NOLOCK)
		WHERE Trans.AccountId = (SELECT DsAccountId FROM #AccountsToRestore)

		UNION

		SELECT TransactionId, ParentTransactionId, TransactionGuid, AccountId, DisbursementAccountId, ReceiptId, TransactionTypeId, Amount, IsReallocated, IsClearedForGoodFunds, IsReversed, TransactionTypeGuid, AllocationTypeId, CreationDateTime, LastEditDateTime
		FROM DebtSettlementLink.DebtSettlement.dbo.VTransactionsLedgerView Trans WITH (NOLOCK)
		WHERE Trans.DisbursementAccountId = (SELECT DsAccountId FROM #AccountsToRestore)

	) Trans
	INNER JOIN TransactionTypes TransTypes WITH(NOLOCK) ON Trans.TransactionTypeId = TransTypes.TransactionTypeId
	ORDER BY TransactionId


--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
-- Find accounts to test transaction type
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------

-------------------------------------------------------
-- Clean up
-------------------------------------------------------
DROP TABLE #AccountsToRestore
DROP TABLE #BalanceForwardAccounts
DROP TABLE #TranList

-------------------------------------------------------
-- Build temp tables
-------------------------------------------------------
SELECT
DmAccounts.AccountUid, 
DmAccounts.AccountId 'DmAccountId',
DmAccounts.AccountCurrentReserveBalance 'DmReserveBalance',
DsAccounts.AccountId 'DsAccountId',
DsAccounts.ReserveBalance 'DsReserveBalance',
AdjustedReserveBalance = DsAccounts.ReserveBalance - ISNULL(Advances.AdvanceBalance, 0),
DsAccounts.ContactId 'DsContactId'
INTO #AccountsToRestore
FROM Account DmAccounts
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.Accounts DsAccounts ON DmAccounts.AccountUid = DsAccounts.AccountGuid
LEFT JOIN DebtSettlementLink.DebtSettlement.dbo.vCorporateAdvancesByAccount Advances ON DsAccounts.AccountId = Advances.AccountId

SELECT AccountId
INTO #BalanceForwardAccounts
FROM LedgerTransactions WHERE Description = 'Balance Forward'

DELETE FROM #AccountsToRestore
WHERE DmAccountId NOT IN (
	SELECT AccountId FROM #BalanceForwardAccounts
	)
AND DmReserveBalance = AdjustedReserveBalance

SELECT DISTINCT DsAccountID = AccountID, Trans.TransactionTypeID, TransTypes.Name
INTO #TranList
FROM DebtSettlementLink.DebtSettlement.dbo.Transactions Trans
INNER JOIN DebtSettlementLink.DebtSettlement.dbo.TransactionTypes TransTypes WITH(NOLOCK) ON Trans.TransactionTypeId = TransTypes.TransactionTypeId
WHERE Trans.TransactionTypeID >=  800

-------------------------------------------------------
-- Display qualifying account by transaction type
-------------------------------------------------------
SELECT TransactionTypeID, Name, COUNT(*)
FROM #AccountsToRestore	T1
JOIN #TranList T2 ON T2.DsAccountID = T1.DsAccountId
GROUP BY TransactionTypeID, Name 
ORDER BY TransactionTypeID 

SELECT *
FROM #AccountsToRestore	T1
JOIN #TranList T2 ON T2.DsAccountID = T1.DsAccountId
WHERE TransactionTypeID =  801



*/



/*
DROP TABLE #AuditSession
DROP TABLE #AccountsOutOfSync
DROP TABLE #AccountsToRestore
DROP TABLE #ActualRunningBalances
DROP TABLE #AdjustmentChildrenToRemove
DROP TABLE #AdjustmentParents
DROP TABLE #AdjustmentParentsToRemove
DROP TABLE #AmountAdjustments
DROP TABLE #BalanceForwardAccounts
DROP TABLE #ChildrenToRemove
DROP TABLE #DebitAllocationNames
DROP TABLE #DisbursementChildrenToRemove
DROP TABLE #DisbursementParents
DROP TABLE #DisbursementParentsToRemove
DROP TABLE #DsTransactions
DROP TABLE #Families
DROP TABLE #FeeReallocationParents
DROP TABLE #LedgerTransactionOrder
DROP TABLE #LedgerTransactionOrderUpdate
DROP TABLE #LedgerTransactionsToRemove
DROP TABLE #Nwr622Fees
DROP TABLE #Nwr638Fees
DROP TABLE #Nwr649Adjustments
DROP TABLE #Nwr649Fees
DROP TABLE #Nwr669Fees
DROP TABLE #NwrAdjustmentFees
DROP TABLE #NwrAssessedFeeAdjustments
DROP TABLE #NwrAssessedFeeReversals
DROP TABLE #NwrFees
DROP TABLE #NwrFeesToRemoveFromLedger
DROP TABLE #NwrManual649Fees
DROP TABLE #NwrManualFees
DROP TABLE #NwrManualFeesToRemoveFromLedger
DROP TABLE #OtherPayeeNames
DROP TABLE #ParentsToRemove
DROP TABLE #PaymentChildrenToRemove
DROP TABLE #PaymentParents
DROP TABLE #PaymentParentsToRemove
DROP TABLE #PossibleResultingTransactionIds
DROP TABLE #ReserveCreditAdjustments
DROP TABLE #ReversedTransactionsNotProperlyDisbursed
DROP TABLE #RunningBalances
DROP TABLE #SettlementPayeeNames
DROP TABLE #TransactionsToRestore
DROP TABLE #TransferChildrenToRemove
DROP TABLE #TransferCreditPayeeNames
DROP TABLE #TransferParents
DROP TABLE #TransferParentsToRemove
DROP TABLE #NewTransferParentsToRemove
DROP TABLE #NewTransferParents
DROP TABLE #NewTransferChildrenToRemove
DROP TABLE #AccountsToRestoreDropList













-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
-- Table size maintenence
-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
DELETE LedgerTransactions_InvalidTransactionList
WHERE SessionId < (
	SELECT MaxSessionId = MAX(SessionId)
	FROM LedgerTransactions_AuditSession
	WHERE dbo.fnDateTrunc(SessionDate) < dbo.fnDateTrunc(DATEADD(Day,-3,GetDate()))
	)



-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
-- Change Schema For Auditing 
-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
-----------------------------------------------------------------------------------
DROP TABLE LedgerTransactions_AuditSession
DROP TABLE LedgerTransactions_AuditHistory
DROP TABLE LedgerTransactions_AuditStatus
DROP TABLE LedgerTransactions_InvalidTransactionList


IF EXISTS(SELECT * FROM VDBObjects WHERE ObjectName = '_LedgerTransactionCorrections') BEGIN 
	EXECUTE sp_rename '_LedgerTransactionCorrections', 'LedgerTransactions_Corrections'
END

IF EXISTS(SELECT * FROM VDBObjects WHERE ObjectName = '_LedgerTransactionsPurged') BEGIN 
	EXECUTE sp_rename '_LedgerTransactionsPurged', 'LedgerTransactions_Purged'
END


IF NOT EXISTS(SELECT * FROM VDBColumns WHERE TableName = 'LedgerTransactions_Corrections' AND ColumnName = 'SessionId') BEGIN 
	ALTER TABLE LedgerTransactions_Corrections ADD SessionId int NULL
END
IF NOT EXISTS(SELECT * FROM VDBColumns WHERE TableName = 'LedgerTransactions_Purged' AND ColumnName = 'SessionId') BEGIN 
	ALTER TABLE LedgerTransactions_Purged ADD SessionId int NULL
END


IF NOT EXISTS(SELECT * FROM VDBObjects WHERE ObjectName = 'LedgerTransactions_AuditSession') BEGIN 
	
	CREATE TABLE LedgerTransactions_AuditSession(
		[SessionId] [int] IDENTITY NOT NULL constraint PK_LedgerTransactions_AuditSession primary key(SessionId),
		[SessionDate] datetime not null constraint DF_LedgerTransactions_AuditSession_SessionDate default GetDate(),
		[SessionComplete] datetime null,
		[AccountsToRestoreTotal] [int] NULL,
		[AccountsConsidered] [int] NULL,
		[BalanceForwardAccounts] [int] NULL
		)
END

IF NOT EXISTS(SELECT * FROM VDBObjects WHERE ObjectName = 'LedgerTransactions_AuditStatus') BEGIN 
	
	CREATE TABLE LedgerTransactions_AuditStatus(
		[AuditStatusId] [tinyint] NOT NULL constraint PK_LedgerTransactions_AuditStatus primary key(AuditStatusId),
		[Description] [varchar](50) NOT NULL
		)

	INSERT LedgerTransactions_AuditStatus(AuditStatusId,[Description]) VALUES(1, 'Balance Forward') 
	INSERT LedgerTransactions_AuditStatus(AuditStatusId,[Description]) VALUES(2, 'Transaction Adjustments') 
	INSERT LedgerTransactions_AuditStatus(AuditStatusId,[Description]) VALUES(3, 'No Action Taken') 
	
	SELECT * FROM LedgerTransactions_AuditStatus		
END

IF NOT EXISTS(SELECT * FROM VDBObjects WHERE ObjectName = 'LedgerTransactions_AuditHistory') BEGIN 
	
	CREATE TABLE LedgerTransactions_AuditHistory(
		[ID] [int] IDENTITY NOT NULL constraint PK_LedgerTransactions_AuditHistory primary key(ID),
		[SessionId] [int] NOT NULL,
		[AccountID] [int] NOT NULL,
		[AuditStatusId] [tinyint] NOT NULL CONSTRAINT FK_LedgerTransactions_AuditHistory_LedgerTransactions_AuditStatus FOREIGN KEY(AuditStatusId) REFERENCES LedgerTransactions_AuditStatus(AuditStatusId),
		[RunningBalanceCalculation] [money] NOT NULL,
		[AdjustedReserveBalance] [money] NOT NULL,
		)
END


IF NOT EXISTS(SELECT * FROM VDBObjects WHERE ObjectName = 'LedgerTransactions_InvalidTransactionList') BEGIN 
	
	CREATE TABLE [dbo].[LedgerTransactions_InvalidTransactionList](
		[Id] [int] IDENTITY NOT NULL constraint PK_LedgerTransactions_InvalidTransactionList primary key(ID),
		--[Id] [int] NULL,
		[TransactionTypeID] [int] NOT NULL,
		[TransactionDate] [datetime] NOT NULL,
		[LedgerTransactionUID] [uniqueidentifier] NOT NULL,
		[PayeeName] [varchar](50) NOT NULL,
		[Amount] [money] NOT NULL,
		[Description] [varchar](50) NULL,
		[RemainingBalance] [money] NULL,
		[ParentID] [int] NULL,
		[HasCleared] [bit] NOT NULL,
		[SequenceNumber] [int] NULL,
		[AccountID] [int] NOT NULL,
		[SessionId] [int] NOT NULL
	)
END


*/






GO


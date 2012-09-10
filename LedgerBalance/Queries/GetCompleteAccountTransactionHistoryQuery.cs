using System;
using System.Collections.Generic;
using System.Linq;
using Dapper;
using Meracord.Transactions.LedgerBalance.Operations;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public class GetCompleteAccountTransactionHistoryQuery
        : IOperation<Transaction>
    {
        private readonly IDebtSettlementConnection _connection;
        private readonly Guid _accountId;

        public GetCompleteAccountTransactionHistoryQuery(IDebtSettlementConnection connection, Guid accountId) {
            _connection = connection;
            _accountId = accountId;
        }

        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> input) {
            using (var conn = _connection.CreateConnection()) {
                conn.Open();

                const string q = @"
                SELECT t.TransactionId
                    , t.ParentTransactionId
                    , t.TransactionGuid
                    , t.AccountId
                    , t.DisbursementAccountId
                    , t.ReceiptId
                    , t.TransactionTypeId
                    , t.Amount
                    , t.IsReallocated
                    , t.IsClearedForGoodFunds
                    , t.IsReversed
                    , t.TransactionTypeGuid
                    , t.AllocationTypeId
                    , t.CreationDateTime
                    , t.LastEditDateTime
                    , dbo.fnDateTrunc(case when Receipts.EffectiveDate is not null then Receipts.EffectiveDate else t.CreationDateTime end) as TransactionDate
	            FROM VTransactionsLedgerView t WITH (NOLOCK)
	            INNER JOIN Accounts ON t.AccountId = Accounts.AccountId
                INNER JOIN Receipts ON t.ReceiptId = Receipts.ReceiptId
                WHERE Accounts.AccountGUID = @AccountGUID

        	    UNION

                SELECT t.TransactionId
                    , t.ParentTransactionId
                    , t.TransactionGuid
                    , t.AccountId
                    , t.DisbursementAccountId
                    , t.ReceiptId
                    , t.TransactionTypeId
                    , t.Amount
                    , t.IsReallocated
                    , t.IsClearedForGoodFunds
                    , t.IsReversed
                    , t.TransactionTypeGuid
                    , t.AllocationTypeId
                    , t.CreationDateTime
                    , t.LastEditDateTime
                    , dbo.fnDateTrunc(case when Receipts.EffectiveDate is not null then Receipts.EffectiveDate else t.CreationDateTime end) as TransactionDate
	            FROM VTransactionsLedgerView t WITH (NOLOCK)
	            INNER JOIN Accounts ON t.DisbursementAccountId = Accounts.AccountId
                INNER JOIN Receipts ON t.ReceiptId = Receipts.ReceiptId
                WHERE Accounts.AccountGUID = @AccountGUID";

                return conn.Query<Transaction>(q, new { AccountGUID = _accountId }).Distinct();
            }
        }
    }
}
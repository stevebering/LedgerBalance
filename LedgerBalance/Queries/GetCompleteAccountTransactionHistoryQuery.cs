using System;
using System.Collections.Generic;
using Dapper;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public interface IGetTransactionContextsQuery
    {
        IEnumerable<TransactionContext> Execute();
    }

    public interface IGetCompleteAccountTransactionHistoryQuery
    {
        IEnumerable<Transaction> Execute(Guid accountId);
    }

    public class GetCompleteAccountTransactionHistoryQuery : IGetCompleteAccountTransactionHistoryQuery
    {
        private readonly IDebtSettlementConnection _connection;

        public GetCompleteAccountTransactionHistoryQuery(IDebtSettlementConnection connection)
        {
            _connection = connection;
        }

        public IEnumerable<Transaction> Execute(Guid accountId)
        {
            var conn = _connection.Connection;
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
	        FROM VTransactionsLedgerView t WITH (NOLOCK)
	        INNER JOIN Accounts ON t.AccountId = Accounts.AccountId
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
	        FROM VTransactionsLedgerView t WITH (NOLOCK)
	        INNER JOIN Accounts ON t.DisbursementAccountId = Accounts.AccountId
            WHERE Accounts.AccountGUID = @AccountGUID";

            return conn.Query<Transaction>(q, new { AccountGUID = accountId });
        }
    }
}
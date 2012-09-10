using System;
using System.Collections.Generic;
using System.Linq;
using Dapper;
using Meracord.Transactions.LedgerBalance.Exceptions;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class ValidateRunningBalance
        : IOperation<Transaction>
    {
        private readonly IDebtSettlementConnection _dsConnection;
        private readonly Guid _accountId;

        public ValidateRunningBalance(IDebtSettlementConnection dsConnection, Guid accountId) {
            _dsConnection = dsConnection;
            _accountId = accountId;
        }

        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> input) {

            DebtSettlementAccount account;

            using (var conn = _dsConnection.CreateConnection()) {
                conn.Open();

                const string q =
                    @"SELECT AccountId
                    , ReserveBalance
                    , ReserveBalance - ISNULL(Advances.AdvanceBalance, 0) as AdjustedReserveBalance
                    , ContactId
                    FROM Account INNER JOIN VCorporateAdvancesByAccount Advances 
                    ON Account.AccountId = Advances.AccountId
                    WHERE Account.AccountGUID = @accountId";

                account = conn
                    .Query<DebtSettlementAccount>(q, new { accountId = _accountId })
                    .Single();
            }

            var latestTransaction = input
                .OrderByDescending(i => i.TransactionDate)
                .ThenByDescending(i => i.TransactionId)
                .FirstOrDefault();

            if (latestTransaction == null) {
                return HandleZeroTransactions(account);
            }

            var balanceOnLastTransaction = latestTransaction.RemainingBalance;
            if (account.AdjustedReserveBalance != balanceOnLastTransaction) {
                // we have a balance problem.
                throw new TransactionsOutOfBalanceException(_accountId, account.AdjustedReserveBalance,
                                                            balanceOnLastTransaction);
            }

            return input;
        }

        private IEnumerable<Transaction> HandleZeroTransactions(DebtSettlementAccount account) {
            if (account.AdjustedReserveBalance != 0.0m) {
                // we have a problem with this account. We have no transactions but a non-zero balance
                throw new MissingTransactionsException(_accountId);
            }

            // no transactions, but a zero balance. Let's insert an initial balance transaction
            var initialBalanceTransaction = new Transaction() {
                RemainingBalance = 0.0m,
                Amount = 0.0m,
                //TODO: add missing details to make up a full transaction when the initial balance transaction is missing
            };

            yield return initialBalanceTransaction;
        }
    }
}
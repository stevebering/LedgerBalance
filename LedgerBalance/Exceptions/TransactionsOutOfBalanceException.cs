using System;

namespace Meracord.Transactions.LedgerBalance.Exceptions
{
    public class TransactionsOutOfBalanceException
        : Exception
    {
        private const string FormatString =
            "Account {0} has a ledger balance of {1} but has a running balance of {2}. Unable to transform correctly.";

        public TransactionsOutOfBalanceException(Guid accountId, decimal ledgerBalance, decimal runningBalance)
            : base(string.Format(FormatString, accountId, ledgerBalance, runningBalance))
        { }
    }
}
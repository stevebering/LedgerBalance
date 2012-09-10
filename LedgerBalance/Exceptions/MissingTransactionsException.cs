using System;

namespace Meracord.Transactions.LedgerBalance.Exceptions
{
    public class MissingTransactionsException
        : Exception
    {
        private const string FormatString = "Account {0} has no transactions but a non-zero balance.";

        public MissingTransactionsException(Guid accountId)
            : base(string.Format(FormatString, accountId))
        { }
    }
}
using System.Collections.Generic;

namespace Meracord.Transactions.LedgerBalance.Filters
{
    public abstract class TransactionFilter
    {
        public abstract IEnumerable<Transaction> Process(IEnumerable<Transaction> transactions);
    }
}
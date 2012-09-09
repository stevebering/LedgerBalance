using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Filters
{
    public class ReallocatedFeeTransactionFilter : TransactionFilter
    {
        public override IEnumerable<Transaction> Process(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions.Where(t => t.IsReallocated && t.AccountId == t.DisbursementAccountId);
            return transactions.Remove(transactionsToRemove);
        }
    }
}
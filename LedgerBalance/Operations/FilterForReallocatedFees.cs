using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class FilterForReallocatedFees : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions.Where(t => t.IsReallocated && t.AccountId == t.DisbursementAccountId);
            return transactions.Except(transactionsToRemove);
        }
    }
}
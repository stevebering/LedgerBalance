using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class FilterForNonReversedFeesIncreasingConsumerReserves
        : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions
                .Where(t => t.TransactionTypeId == 634)
                .Where(t => t.IsReversed == false)
                .Where(t => t.AccountId == t.DisbursementAccountId);

            return transactions.Except(transactionsToRemove);
        }
    }
}
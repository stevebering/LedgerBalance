using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Filters
{
    public class NonReversedFeesIncreasingConsumerReservesFilter
        : TransactionFilter
    {
        public override IEnumerable<Transaction> Process(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions
                .Where(t => t.TransactionTypeId == 634)
                .Where(t => t.IsReversed == false)
                .Where(t => t.AccountId == t.DisbursementAccountId);

            return transactions.Except(transactionsToRemove);
        }
    }
}
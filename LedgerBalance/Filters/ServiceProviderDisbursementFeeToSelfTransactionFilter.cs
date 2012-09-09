using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Filters
{
    public class ServiceProviderDisbursementFeeToSelfTransactionFilter : TransactionFilter
    {
        public override IEnumerable<Transaction> Process(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions.Where(t => t.TransactionTypeId == 635 && t.AccountId == t.DisbursementAccountId);
            return transactions.Except(transactionsToRemove);
        }
    }
}
using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Filters
{
    public class ServiceProviderActivationFeeToSelfTransactionFilter : TransactionFilter
    {
        public override IEnumerable<Transaction> Process(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions.Where(t => t.TransactionTypeId == 631 && t.AccountId == t.DisbursementAccountId);
            return transactions.Except(transactionsToRemove);
        }
    }
}
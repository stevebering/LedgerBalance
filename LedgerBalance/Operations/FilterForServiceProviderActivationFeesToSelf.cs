using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class FilterForServiceProviderActivationFeesToSelf : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions.Where(t => t.TransactionTypeId == 631 && t.AccountId == t.DisbursementAccountId);
            return transactions.Except(transactionsToRemove);
        }
    }
}
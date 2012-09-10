using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class FilterForServiceProviderDisbursementFeesToSelf : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> transactions)
        {
            var transactionsToRemove = transactions.Where(t => t.TransactionTypeId == 635 && t.AccountId == t.DisbursementAccountId);
            return transactions.Except(transactionsToRemove);
        }
    }
}
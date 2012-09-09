using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Filters
{
    public static class TransactionExtensions
    {
        public static IEnumerable<Transaction> Remove(this IEnumerable<Transaction> transactions, IEnumerable<Transaction> transactionsToRemove)
        {
            return transactions.Where(t => !transactionsToRemove.Any(ttr => ttr.TransactionId == t.TransactionId));
        }

        public static IEnumerable<ParentTransaction> Transform(this IEnumerable<Transaction> parents, IEnumerable<Transaction> transactions)
        {
            var parentList = new List<ParentTransaction>();
            foreach (var parent in parents)
            {
                if (PaymentTransaction.Qualifies(parent))
                {
                    parentList.Add(new PaymentTransaction(parent, transactions));
                    continue;
                }

                if (DisbursementTransaction.Qualifies(parent))
                {
                    parentList.Add(new DisbursementTransaction(parent, transactions));
                    continue;
                }

                if (AdjustmentTransaction.Qualifies(parent))
                {
                    parentList.Add(new AdjustmentTransaction(parent, transactions));
                    continue;
                }

                if (TransferTransaction.Qualifies(parent))
                {
                    parentList.Add(new TransferTransaction(parent, transactions));
                    continue;
                }
            }

            return parentList;
        }
    }
}
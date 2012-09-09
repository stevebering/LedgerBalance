using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance
{
    public class PaymentTransaction : ParentTransaction
    {
        public PaymentTransaction(Transaction parent, IEnumerable<Transaction> transactions)
        {
            this.Parent = parent;
            foreach (var child in transactions.Where(x => x.ParentTransactionId == parent.TransactionId))
            {
                this.AddChild(child);
            }
        }

        public static bool Qualifies(Transaction t)
        {
            var validTypes = new[] { 601, 602, 603 };
            return validTypes.Any(v => v == t.TransactionTypeId);
        }

        public void Filter(IEnumerable<TransactionContextTransactionType> transactionTypes)
        {
            // get a list of transactions to remove, that are not available in the context
            var transactionsFromThisAccount = from child in this.Children
                                              join transactionType in transactionTypes
                                                  on child.TransactionTypeId equals transactionType.TransactionTypeId
                                              select child;

            var transactionsToThisAccount = from child in this.Children
                                            join transactionType in transactionTypes
                                                on child.TransactionTypeId equals transactionType.TransactionTypeId
                                            where transactionType.TransactionTypeId == 638
                                            && child.AccountId == child.DisbursementAccountId
                                            select child;

        }
    }
}
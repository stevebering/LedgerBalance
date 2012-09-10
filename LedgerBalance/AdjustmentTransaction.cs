using System.Collections.Generic;
using System.Linq;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance
{
    public class AdjustmentTransaction : ParentTransaction
    {
        public AdjustmentTransaction(Transaction parent, IEnumerable<Transaction> transactions) {
            this.Parent = parent;
            foreach (var child in transactions.Where(x => x.ParentTransactionId == parent.TransactionId)) {
                this.AddChild(child);
            }
        }

        public static bool Qualifies(Transaction t) {
            var validTypes = new[] { 600, 646, 636, 650, 700 };
            return validTypes.Any(v => v == t.TransactionTypeId);
        }

        public override void FilterChildren(IGetTransactionContextTransactionsTypes transactionTypesQuery) {

        }
    }
}
using System.Collections.Generic;
using System.Linq;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance
{
    public class TransferTransaction : ParentTransaction
    {
        public TransferTransaction(Transaction parent, IEnumerable<Transaction> transactions) {
            this.Parent = parent;
            foreach (var child in transactions.Where(x => x.ParentTransactionId == parent.TransactionId)) {
                this.AddChild(child);
            }
        }

        public static bool Qualifies(Transaction t) {
            var validTypes = new[] { 652, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809 };
            return validTypes.Any(v => v == t.TransactionTypeId);
        }

        public override void FilterChildren(IGetTransactionContextTransactionsTypes transactionTypesQuery) {
        }
    }
}
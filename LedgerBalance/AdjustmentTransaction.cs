using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance
{
    public class AdjustmentTransaction : ParentTransaction
    {
        public AdjustmentTransaction(Transaction parent, IEnumerable<Transaction> transactions)
        {
            this.TransactionId = parent.TransactionId;
            this.ParentTransactionId = parent.ParentTransactionId;
            this.TransactionGuid = parent.TransactionGuid;
            this.AccountId = parent.AccountId;
            this.DisbursementAccountId = parent.DisbursementAccountId;
            this.ReceiptId = parent.ReceiptId;
            this.TransactionTypeId = parent.TransactionTypeId;
            this.Amount = parent.Amount;
            this.IsReallocated = parent.IsReallocated;
            this.IsClearedForGoodFunds = parent.IsClearedForGoodFunds;
            this.IsReversed = parent.IsReversed;
            this.TransactionTypeGuid = parent.TransactionTypeGuid;
            this.AllocationTypeId = parent.AllocationTypeId;
            this.CreationDateTime = parent.CreationDateTime;
            this.LastEditDateTime = parent.LastEditDateTime;

            foreach (var child in transactions.Where(x => x.ParentTransactionId == parent.TransactionId))
            {
                this.AddChild(child);
            }
        }

        public static bool Qualifies(Transaction t)
        {
            var validTypes = new[] { 600, 646, 636, 650, 700 };
            return validTypes.Any(v => v == t.TransactionTypeId);
        }
    }
}
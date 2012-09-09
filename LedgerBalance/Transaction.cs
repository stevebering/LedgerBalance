using System;
using System.Collections.Generic;

namespace Meracord.Transactions.LedgerBalance
{
    public class Transaction
    {
        public int TransactionId { get; set; }
        public int? ParentTransactionId { get; set; }
        public Guid TransactionGuid { get; set; }
        public int AccountId { get; set; }
        public int DisbursementAccountId { get; set; }
        public int ReceiptId { get; set; }
        public int TransactionTypeId { get; set; }
        public decimal Amount { get; set; }
        public bool IsReallocated { get; set; }
        public bool IsClearedForGoodFunds { get; set; }
        public bool IsReversed { get; set; }
        public Guid TransactionTypeGuid { get; set; }
        public int AllocationTypeId { get; set; }
        public DateTime CreationDateTime { get; set; }
        public DateTime LastEditDateTime { get; set; }
    }

    public abstract class ParentTransaction : Transaction
    {
        private readonly IList<Transaction> _children = new List<Transaction>();
        public IEnumerable<Transaction> Children { get { return _children; } }

        public void AddChild(Transaction transaction)
        {
            _children.Add(transaction);
        }
    }
}
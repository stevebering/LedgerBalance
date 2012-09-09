using System;

namespace Meracord.Transactions.LedgerBalance
{
    public class TransactionType
    {
        public int TransactionTypeId { get; set; }
        public Guid TransactionTypeGuid { get; set; }
        public int TransactionCategoryId { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public bool IsLedgerTransaction { get; set; }
        public bool CanRollup { get; set; }
    }
}
namespace Meracord.Transactions.LedgerBalance
{
    public class TransactionContextTransactionType
    {
        public int Id { get; set; }
        public int TransactionContextId { get; set; }
        public int TransactionTypeId { get; set; }
        public bool ReverseSign { get; set; }
    }
}
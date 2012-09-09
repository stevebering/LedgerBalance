namespace Meracord.Transactions.LedgerBalance
{
    public class DebtSettlementAccount
    {
        public int AccountId { get; set; }
        public decimal ReserveBalance { get; set; }
        public decimal AdjustedReserveBalance { get; set; }
        public int ContactId { get; set; }
    }
}
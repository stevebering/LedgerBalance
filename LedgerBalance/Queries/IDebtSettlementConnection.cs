using System.Data.SqlClient;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public interface IDebtSettlementConnection
    {
        SqlConnection CreateConnection();
    }
}
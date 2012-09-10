using System.Data.SqlClient;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public interface IDebtManagerConnectionFactory
    {
        SqlConnection CreateConnection();
    }
}
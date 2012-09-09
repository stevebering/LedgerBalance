using System.Data.SqlClient;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public interface IDebtManagerConnection
    {
        SqlConnection Connection { get; }
    }
}
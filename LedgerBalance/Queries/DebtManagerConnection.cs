using System.Configuration;
using System.Data.SqlClient;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public class DebtManagerConnection : IDebtManagerConnection
    {
        public SqlConnection Connection
        {
            get
            {
                var connectionString = ConfigurationManager.ConnectionStrings["DebtManager"];
                return new SqlConnection(connectionString.ConnectionString);
            }
        }
    }
}
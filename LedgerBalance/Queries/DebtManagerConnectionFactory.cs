using System.Configuration;
using System.Data.SqlClient;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public class DebtManagerConnectionFactory : IDebtManagerConnectionFactory
    {
        public SqlConnection CreateConnection() {
            var connectionString = ConfigurationManager.ConnectionStrings["DebtManager"];
            return new SqlConnection(connectionString.ConnectionString);
        }
    }
}
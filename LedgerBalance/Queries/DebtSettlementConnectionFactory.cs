using System.Configuration;
using System.Data.SqlClient;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public class DebtSettlementConnectionFactory : IDebtSettlementConnection
    {
        public SqlConnection CreateConnection() {
            var connectionString = ConfigurationManager.ConnectionStrings["DebtSettlement"];
            return new SqlConnection(connectionString.ConnectionString);
        }
    }
}
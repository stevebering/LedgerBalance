using System.Configuration;
using System.Data.SqlClient;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public class DebtSettlementConnection : IDebtSettlementConnection
    {
        public SqlConnection Connection
        {
            get
            {
                var connectionString = ConfigurationManager.ConnectionStrings["DebtSettlement"];
                return new SqlConnection(connectionString.ConnectionString);
            }
        }
    }
}
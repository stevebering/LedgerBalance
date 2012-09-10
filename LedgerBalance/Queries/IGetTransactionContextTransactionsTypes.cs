using System;
using System.Collections.Generic;
using Dapper;

namespace Meracord.Transactions.LedgerBalance.Queries
{
    public interface IGetTransactionContextTransactionsTypes
    {
        IEnumerable<TransactionContextTransactionType> FindForContext(int contextTypeId);
    }

    public class TransactionContextTransactionsTypesQuery : IGetTransactionContextTransactionsTypes
    {
        private readonly IDebtManagerConnectionFactory _connFactory;

        public TransactionContextTransactionsTypesQuery(IDebtManagerConnectionFactory connFactory) {
            _connFactory = connFactory;
        }

        public IEnumerable<TransactionContextTransactionType> FindForContext(int contextTypeId) {

            using (var conn = _connFactory.CreateConnection()) {
                conn.Open();

                const string q =
                    @"SELECT Id, TransactionContextId, TransactionTypeId, ReverseSign FROM TransactionContextTransactionTypes 
                WHERE TransactionContextId = @contextTypeId";

                return conn.Query<TransactionContextTransactionType>(q, new { contextTypeId = contextTypeId });
            }
        }
    }
}
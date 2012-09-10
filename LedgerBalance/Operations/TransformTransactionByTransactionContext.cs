using System.Collections.Generic;
using System.Linq;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class TransformTransactionByTransactionContext
        : IOperation<Transaction>
    {
        private readonly IDebtManagerConnectionFactory _debtManagerConnectionFactory;
        private readonly IGetTransactionContextTransactionsTypes _transactionsTypesQuery;

        public TransformTransactionByTransactionContext(IDebtManagerConnectionFactory debtManagerConnectionFactory) {
            _debtManagerConnectionFactory = debtManagerConnectionFactory;
            _transactionsTypesQuery = new TransactionContextTransactionsTypesQuery(_debtManagerConnectionFactory);
        }

        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> input) {
            var parents = BuildTransactionContexts(input);

            parents = RemoveTransactionsByTransactionContext(_debtManagerConnectionFactory, parents);

            return FlattenTransactionList(parents);
        }

        private IEnumerable<Transaction> FlattenTransactionList(List<ParentTransaction> parents) {
            var parentTransactions = new List<Transaction>(parents.Select(p => p.Parent));
            var childTransactions = new List<Transaction>(parents.SelectMany(p => p.Children));

            return parentTransactions.Union(childTransactions);
        }

        private List<ParentTransaction> RemoveTransactionsByTransactionContext(IDebtManagerConnectionFactory debtManagerConnectionFactory, List<ParentTransaction> parents) {
            foreach (ParentTransaction parent in parents) {
                parent.FilterChildren(_transactionsTypesQuery);
            }

            return parents;
        }

        private static List<ParentTransaction> BuildTransactionContexts(IEnumerable<Transaction> input) {
            var parents = input.Where(t => t.ParentTransactionId == null).ToList();
            var parentList = new List<ParentTransaction>();

            foreach (var parent in parents) {
                if (PaymentTransaction.Qualifies(parent)) {
                    parentList.Add(new PaymentTransaction(parent, input));
                    continue;
                }

                if (DisbursementTransaction.Qualifies(parent)) {
                    parentList.Add(new DisbursementTransaction(parent, input));
                    continue;
                }

                if (AdjustmentTransaction.Qualifies(parent)) {
                    parentList.Add(new AdjustmentTransaction(parent, input));
                    continue;
                }

                if (TransferTransaction.Qualifies(parent)) {
                    parentList.Add(new TransferTransaction(parent, input));
                    continue;
                }
            }

            return parentList;
        }
    }
}
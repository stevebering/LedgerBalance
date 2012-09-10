using System.Collections.Generic;
using System.Linq;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class TransformTransactionByTransactionContext
        : IOperation<Transaction>
    {
        private readonly IDebtManagerConnection _debtManagerConnection;

        public TransformTransactionByTransactionContext(IDebtManagerConnection debtManagerConnection)
        {
            _debtManagerConnection = debtManagerConnection;
        }

        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> input)
        {
            var parents = BuildTransactionContexts(input);

            parents = RemoveTransactionsByTransactionContext(_debtManagerConnection, parents);

            return FlattenTransactionList(parents);
        }

        private IEnumerable<Transaction> FlattenTransactionList(List<ParentTransaction> parents)
        {
            throw new System.NotImplementedException();
        }

        private List<ParentTransaction> RemoveTransactionsByTransactionContext(IDebtManagerConnection debtManagerConnection, List<ParentTransaction> parents)
        {
            throw new System.NotImplementedException();
        }

        private static List<ParentTransaction> BuildTransactionContexts(IEnumerable<Transaction> input)
        {
            var parents = input.Where(t => t.ParentTransactionId == null).ToList();
            var parentList = new List<ParentTransaction>();

            foreach (var parent in parents)
            {
                if (PaymentTransaction.Qualifies(parent))
                {
                    parentList.Add(new PaymentTransaction(parent, input));
                    continue;
                }

                if (DisbursementTransaction.Qualifies(parent))
                {
                    parentList.Add(new DisbursementTransaction(parent, input));
                    continue;
                }

                if (AdjustmentTransaction.Qualifies(parent))
                {
                    parentList.Add(new AdjustmentTransaction(parent, input));
                    continue;
                }

                if (TransferTransaction.Qualifies(parent))
                {
                    parentList.Add(new TransferTransaction(parent, input));
                    continue;
                }
            }

            return parentList;
        }
    }
}
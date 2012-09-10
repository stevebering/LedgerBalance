using System.Collections.Generic;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public interface IOperation<T>
    {
        IEnumerable<T> Execute(IEnumerable<T> input);
    }
}
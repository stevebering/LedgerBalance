using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class CalculateRunningBalance
        : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> input)
        {
            var orderedInput = input.OrderBy(i => i.TransactionDate).ThenBy(i => i.TransactionId);
            decimal runningBalance = 0.0m;
            foreach (var transaction in orderedInput)
            {
                var itemBalance = decimal.Round(runningBalance + transaction.Amount, 2);
                runningBalance = itemBalance;
                transaction.RemainingBalance = runningBalance;

                yield return transaction;
            }
        }
    }
}
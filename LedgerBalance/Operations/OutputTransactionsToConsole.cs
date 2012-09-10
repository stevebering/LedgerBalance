using System;
using System.Collections.Generic;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class OutputTransactionsToConsole
        : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> input)
        {
            foreach (var item in input)
            {
                Console.WriteLine("ID: {0}; Date: {1:D}; Amount: {2:0.00}; Balance: {3:0.00}",
                                  item.TransactionId, item.TransactionDate, item.Amount, item.RemainingBalance);
            }

            yield break;
        }
    }
}
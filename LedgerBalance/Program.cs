using System;

namespace Meracord.Transactions.LedgerBalance
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args == null || args.Length < 1)
            {
                throw new ArgumentOutOfRangeException("args", "Expected account UID to be provided, but it was not.");
            }

            var value = args[0];
            Guid accountId;

            if (!Guid.TryParse(value, out accountId))
            {
                throw new ArgumentOutOfRangeException("args", "Expected account UID to be a Guid, but it was {0}", value);
            }

            var balancer = new TransactionBalancer(accountId);
            balancer.Execute();
        }
    }
}

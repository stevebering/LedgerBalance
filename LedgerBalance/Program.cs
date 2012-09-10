using System;

namespace Meracord.Transactions.LedgerBalance
{
    class Program
    {
        static void Main(string[] args) {
            string value;
            if (args == null || args.Length < 1) {
                Console.WriteLine("Enter the unique identifier of the account that you want to balance.");
                value = Console.ReadLine();
            }
            else {
                value = args[0];
            }

            Guid accountId;

            if (!Guid.TryParse(value, out accountId)) {
                throw new ArgumentOutOfRangeException("args", "Expected account UID to be a Guid, but it was {0}", value);
            }

            var balancer = new TransactionBalancer(accountId);
            balancer.Execute();
        }
    }
}

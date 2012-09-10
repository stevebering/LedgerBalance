using System;
using Meracord.Transactions.LedgerBalance.Operations;

namespace Meracord.Transactions.LedgerBalance
{
    public class TransactionBalancer
    {
        private readonly Guid _accountId;

        public TransactionBalancer(Guid accountId)
        {
            _accountId = accountId;
        }

        public void Execute()
        {
            if (_accountId == Guid.Empty)
            {
                throw new ApplicationException("Expected to be provided account GUID, but it was not provided.");
            }

            var pipeline = new TransactionPipeline(_accountId);
            pipeline.Execute();

            Console.ReadLine();
        }
    }
}
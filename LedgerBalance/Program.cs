using System;
using System.Collections.Generic;
using System.Linq;
using Meracord.Transactions.LedgerBalance.Filters;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance
{
    class Program
    {
        static void Main(string[] args)
        {
            var balancer = new TransactionBalancer(args);
            balancer.Execute();
        }
    }

    public class TransactionBalancer
    {
        private readonly Guid _accountId;
        private IGetCompleteAccountTransactionHistoryQuery _transactionQuery;

        public TransactionBalancer(string[] args)
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

            _accountId = accountId;
        }

        private void SetupDependencies()
        {
            var debtSettlementConnection = new DebtSettlementConnection();
            var debtManagerConnection = new DebtManagerConnection();

            _transactionQuery = new GetCompleteAccountTransactionHistoryQuery(debtSettlementConnection);
        }

        public void Execute()
        {
            if (_accountId == Guid.Empty)
            {
                throw new ApplicationException("Expected to be provided account GUID, but it was not provided.");
            }

            SetupDependencies();

            var fullTransactionList = _transactionQuery.Execute(_accountId);

            var filters = new List<TransactionFilter>
                              {
                                  new Filters.NonReversedFeesIncreasingConsumerReservesFilter(),
                                  new Filters.AssessedProcessingFeeTransactionFilter(),
                                  new Filters.ManualFeeTransactionFilter(),
                                  new Filters.ReallocatedFeeTransactionFilter(),
                                  new Filters.ServiceProviderActivationFeeToSelfTransactionFilter(),
                                  new Filters.ServiceProviderDisbursementFeeToSelfTransactionFilter()
                              };

            var transactions = filters.Aggregate(fullTransactionList, (current, filter) => filter.Process(current));

            var parentTransactions = transactions
                .Where(t => t.ParentTransactionId == null)
                .Transform(transactions);
        }
    }
}

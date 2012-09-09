using System;
using System.Collections.Generic;
using System.Diagnostics;
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


            IEnumerable<Transaction> fullTransactionList;
            using (var timer = new ProcessTimer())
            {
                fullTransactionList = _transactionQuery.Execute(_accountId);
                LogProcess("GetCompleteAccountTransactionHistory", timer);
            }


            List<TransactionFilter> filters;
            using (var timer = new ProcessTimer())
            {
                filters = new List<TransactionFilter>
                              {
                                  new Filters.NonReversedFeesIncreasingConsumerReservesFilter(),
                                  new Filters.AssessedProcessingFeeTransactionFilter(),
                                  new Filters.ManualFeeTransactionFilter(),
                                  new Filters.ReallocatedFeeTransactionFilter(),
                                  new Filters.ServiceProviderActivationFeeToSelfTransactionFilter(),
                                  new Filters.ServiceProviderDisbursementFeeToSelfTransactionFilter()
                              };
                LogProcess("Building Filters", timer);
            }

            List<Transaction> transactions;
            using (var timer = new ProcessTimer())
            {
                transactions =
                    filters.Aggregate(fullTransactionList, (current, filter) => filter.Process(current)).ToList();
                LogProcess("Executing Filters", timer);
            }
            
            List<ParentTransaction> parentTransactions;
            using (var timer = new ProcessTimer())
            {
                parentTransactions = transactions
                    .Where(t => t.ParentTransactionId == null)
                    .Transform(transactions).ToList();
                LogProcess("Building parent relationships", timer);
            }

            foreach (var parent in parentTransactions)
            {
                Console.WriteLine("Found parent of type '{0}' with {1} children.", parent.GetType().Name,
                                  parent.Children.Count());
            }

            Console.ReadLine();
        }

        private void LogProcess(string processName, ProcessTimer timer)
        {
            var duration = timer.Complete();
            Console.WriteLine("Finished '{0}' in {1} seconds.", processName, duration.TotalSeconds);
        }

        public class ProcessTimer : IDisposable
        {
            private readonly Stopwatch _stopwatch;

            public ProcessTimer()
            {
                _stopwatch = new Stopwatch();
                _stopwatch.Start();
            }

            public void Dispose()
            {
                _stopwatch.Reset();
            }

            public TimeSpan Complete()
            {
                _stopwatch.Stop();
                return _stopwatch.Elapsed;
            }
        }


    }
}

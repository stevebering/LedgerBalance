using System;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class TransactionPipeline
        : Pipeline<Transaction>
    {
        private readonly DebtSettlementConnectionFactory _debtSettlementConnectionFactory;
        private readonly DebtManagerConnectionFactory _debtManagerConnectionFactory;

        public TransactionPipeline(Guid accountId) {
            _debtSettlementConnectionFactory = new DebtSettlementConnectionFactory();
            _debtManagerConnectionFactory = new DebtManagerConnectionFactory();

            // get our first input element with the full list of transactions
            Register(new GetCompleteAccountTransactionHistoryQuery(_debtSettlementConnectionFactory, accountId));

            Register(new FilterForNonReversedFeesIncreasingConsumerReserves());
            Register(new FilterForAssessedProcessingFee());
            Register(new FilterForManualFeeAssessments());
            Register(new FilterForReallocatedFees());
            Register(new FilterForServiceProviderActivationFeesToSelf());
            Register(new FilterForServiceProviderDisbursementFeesToSelf());

            // remove transactions by transaction context, just like messaging does
            Register(new TransformTransactionByTransactionContext(_debtManagerConnectionFactory));

            // validate our input against the balance stored in debtsettlement
            Register(new CalculateRunningBalance());
            Register(new ValidateRunningBalance(_debtSettlementConnectionFactory, accountId));

            // update the transactions in debtmanager with our changed values

            // output each item to the console
            Register(new OutputTransactionsToConsole());
        }
    }
}
using System;
using Meracord.Transactions.LedgerBalance.Queries;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class TransactionPipeline
        : Pipeline<Transaction>
    {
        private readonly DebtSettlementConnection _debtSettlementConnection;
        private readonly DebtManagerConnection _debtManagerConnection;

        public TransactionPipeline(Guid accountId)
        {
            _debtSettlementConnection = new DebtSettlementConnection();
            _debtManagerConnection = new DebtManagerConnection();

            // get our first input element with the full list of transactions
            Register(new GetCompleteAccountTransactionHistoryQuery(_debtSettlementConnection, accountId));

            Register(new FilterForNonReversedFeesIncreasingConsumerReserves());
            Register(new FilterForAssessedProcessingFee());
            Register(new FilterForManualFeeAssessments());
            Register(new FilterForReallocatedFees());
            Register(new FilterForServiceProviderActivationFeesToSelf());
            Register(new FilterForServiceProviderDisbursementFeesToSelf());

            // remove transactions by transaction context, just like messaging does
            Register(new TransformTransactionByTransactionContext(_debtManagerConnection));

            // validate our input against the balance stored in debtsettlement
            Register(new CalculateRunningBalance());
            Register(new ValidateRunningBalance(_debtSettlementConnection, accountId));

            // update the transactions in debtmanager with our changed values

            // output each item to the console
            Register(new OutputTransactionsToConsole());
        }
    }
}
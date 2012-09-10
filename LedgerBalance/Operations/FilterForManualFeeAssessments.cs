using System;
using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class FilterForManualFeeAssessments
        : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> transactions) {
            var manualFees = transactions.Where(t => t.TransactionTypeId == 669);
            var assessedFees = transactions.Where(t => t.TransactionTypeId == 649);

            var manualAssessedFees = from manualFee in manualFees
                                     from assessedFee in assessedFees
                                     where FeesMatch(manualFee, assessedFee)
                                     select manualFee;

            return transactions.Except(manualAssessedFees);
        }

        private bool FeesMatch(Transaction manualFee, Transaction assessedFee) {
            if (manualFee.ParentTransactionId != assessedFee.ParentTransactionId) {
                // they can't match if they have different parents
                return false;
            }

            if (manualFee.IsReversed != assessedFee.IsReversed) {
                // they can't match if only one was reversed
                return false;
            }

            if (manualFee.CreationDateTime.Subtract(assessedFee.CreationDateTime) >= TimeSpan.FromSeconds(90)) {
                // if they weren't created together, they can't match
                return false;
            }

            if (manualFee.Amount >= (assessedFee.Amount * -1)) {
                // fee assessment could be for only part of the manual fee anount
                return true;
            }

            return false;
        }
    }
}
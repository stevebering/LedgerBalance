using System;
using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Operations
{
    public class FilterForAssessedProcessingFee
        : IOperation<Transaction>
    {
        public IEnumerable<Transaction> Execute(IEnumerable<Transaction> transactions) {
            // get all 638 fees and corresponding 649 transactions, even split 649 fees
            var meracordFees = transactions.Where(x => x.TransactionTypeId == 638).ToList();
            var assessedFees = transactions.Where(x => x.TransactionTypeId == 649).ToList();

            var feesWithMatchingAllocation = meracordFees.Where(meracordFee => assessedFees.Any(assessedFee => FeesMatch(meracordFee, assessedFee)));

            var remainingTransactions = transactions.Except(feesWithMatchingAllocation);

            // remove fees that are not from and to the same account

            // update the transaction amount if part of the fee was paid by the service provider


            return remainingTransactions;
        }

        private bool FeesMatch(Transaction meracordFee, Transaction assessedFee) {
            if (meracordFee.ParentTransactionId != assessedFee.ParentTransactionId) {
                // they would have the same parents, if they match
                return false;
            }

            if (meracordFee.IsReversed != assessedFee.IsReversed) {
                // either none or both would be reversed if they match
                return false;
            }

            if (meracordFee.Amount > (assessedFee.Amount * -1)) {
                // if the amounts are not comparable, it doesn't match
                return false;
            }

            if (assessedFee.DisbursementAccountId == 2) {
                // if doesn't count if the fee was not assessed to the Meracord fee account
                return false;
            }

            if (meracordFee.TransactionId < assessedFee.TransactionId) {
                return false;
            }

            if (assessedFee.CreationDateTime.Subtract(meracordFee.CreationDateTime) >= TimeSpan.FromSeconds(90)) {
                return false;
            }

            return true;
        }
    }
}
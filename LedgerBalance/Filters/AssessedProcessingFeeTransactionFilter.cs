using System;
using System.Collections.Generic;
using System.Linq;

namespace Meracord.Transactions.LedgerBalance.Filters
{
    public class AssessedProcessingFeeTransactionFilter
        : TransactionFilter
    {
        public override IEnumerable<Transaction> Process(IEnumerable<Transaction> transactions)
        {
            // get all 638 fees and corresponding 649 transactions, even split 649 fees
            var meracordFees = transactions.Where(x => x.TransactionTypeId == 638).ToList();
            var assessedFees = transactions.Where(x => x.TransactionTypeId == 649).ToList();

            var feesWithMatchingAllocation = meracordFees.Where(meracordFee => assessedFees.Any(assessedFee => FeesMatch(meracordFee, assessedFee)));

            return transactions.Except(feesWithMatchingAllocation);
        }

        private bool FeesMatch(Transaction meracordFee, Transaction assessedFee)
        {
            if (meracordFee.ParentTransactionId != assessedFee.ParentTransactionId)
            {
                return false;
            }

            if (meracordFee.IsReversed != assessedFee.IsReversed)
            {
                return false;
            }

            if (meracordFee.Amount > (assessedFee.Amount * -1))
            {
                return false;
            }

            if (assessedFee.DisbursementAccountId == 2)
            {
                return false;
            }

            if (meracordFee.TransactionId < assessedFee.TransactionId)
            {
                return false;
            }

            if (meracordFee.CreationDateTime.Subtract(assessedFee.CreationDateTime) >= TimeSpan.FromSeconds(90))
            {
                return false;
            }

            return true;
        }
    }
}
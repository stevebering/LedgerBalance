using System;
using System.Collections.Generic;
using Meracord.Transactions.LedgerBalance.Operations;

namespace Meracord.Transactions.LedgerBalance
{
    public class Pipeline<T>
    {
        private readonly IList<IOperation<T>> _operations = new List<IOperation<T>>();

        public Pipeline<T> Register(IOperation<T> operation) {
            _operations.Add(operation);
            return this;
        }

        public void Execute() {
            IEnumerable<T> current = new List<T>();
            foreach (var operation in _operations) {
                using (var timer = new ProcessTimer()) {
                    current = operation.Execute(current);
                    var duration = timer.Complete();
                    Console.WriteLine("Operation '{0}' completed in {1:0.0 seconds}.", operation.GetType().Name,
                                      duration.TotalSeconds);
                }
            }
            IEnumerator<T> enumerator = current.GetEnumerator();
            while (enumerator.MoveNext()) ;
        }
    }
}
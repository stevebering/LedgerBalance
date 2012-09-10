using System;
using System.Diagnostics;

namespace Meracord.Transactions.LedgerBalance
{
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
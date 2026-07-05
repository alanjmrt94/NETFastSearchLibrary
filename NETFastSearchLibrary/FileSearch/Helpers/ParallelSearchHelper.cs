using System;

namespace NETFastSearchLibrary
{
    /// <summary>
    /// Límites de paralelismo para búsquedas multi-hilo.
    /// </summary>
    internal static class ParallelSearchHelper
    {
        /// <summary>
        /// Grado máximo de paralelismo acotado al número de procesadores.
        /// </summary>
        public static int MaxDegreeOfParallelism
        {
            get { return Math.Max(1, Environment.ProcessorCount); }
        }
    }
}

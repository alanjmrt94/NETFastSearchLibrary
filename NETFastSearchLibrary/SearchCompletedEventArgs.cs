using System;

namespace NETFastSearchLibrary
{
    /// <summary>
    /// Proporciona datos para el evento <see cref="FileSearch.SearchCompleted"/>.
    /// </summary>
    public class SearchCompletedEventArgs : EventArgs
    {
        /// <summary>
        /// Indica si la búsqueda finalizó porque se llamó a <see cref="FileSearch.StopSearch"/>.
        /// </summary>
        public bool IsCanceled { get; private set; }

        /// <summary>
        /// Inicializa una nueva instancia de <see cref="SearchCompletedEventArgs"/>.
        /// </summary>
        /// <param name="isCanceled"><c>true</c> si la búsqueda fue cancelada; en caso contrario, <c>false</c>.</param>
        public SearchCompletedEventArgs(bool isCanceled)
        {
            IsCanceled = isCanceled;
        }
    }
}

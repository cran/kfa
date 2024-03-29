% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/find_k.R
\name{find_k}
\alias{find_k}
\title{Find k for k-fold cross-validation}
\usage{
find_k(
  variables,
  n,
  p,
  m = NULL,
  max.k = 10,
  min.n = 200,
  rmsea0 = 0.05,
  rmseaA = 0.08,
  ...
)
}
\arguments{
\item{variables}{a \code{data.frame} (or convertible to a \code{data.frame}) with variables to factor analyze in columns and observations in rows.
The power analysis assumes all observations have complete data. Use \code{n} argument or remove rows manually to account for missingness.}

\item{n}{integer; number of observations. Ignored if \code{variables} is provided.}

\item{p}{integer; number of variables to factor analyze. Ignored if\code{variables} is provided.}

\item{m}{integer; maximum number of factors expected to be extracted from \code{variables}. Default is \code{p} / 4 (i.e., 4 variables per factor).}

\item{max.k}{integer; maximum number of folds. Default is 10. \code{NULL} indicates no maximum.}

\item{min.n}{integer; minimum sample size per fold. Default is 200 based on simulations from Curran et al. (2003).}

\item{rmsea0}{numeric; RMSEA under the null hypothesis.}

\item{rmseaA}{numeric; RMSEA under the alternative hypothesis.}

\item{...}{other arguments passed to \code{\link[semTools]{findRMSEAsamplesize}}.}
}
\value{
named vector with the number of folds (k), sample size suggested by the power analysis (power.n), and the actual sample size used for determining k (actual.n).
}
\description{
This function is specifically for determining \emph{k} in the context of factor analysis using
change in RMSEA as the criterion for identifying the optimal factor model.
}
\examples{
find_k(n = 900, p = 20, m = 3)

# adjust precision
find_k(n = 900, p = 20, m = 3, rmsea0 = .03, rmseaA = .10)

}
\references{
Curran, P. J., Bollen, K. A., Chen, F., Paxton, P., & Kirby, J. B. (2003). Finite sampling properties of the point estimates and confidence intervals of the RMSEA. \emph{Sociological Methods & Research, 32}(2), 208-252. \doi{10.1177/0049124103256130}

MacCallum, R. C., Browne, M. W., & Sugawara, H. M. (1996). Power analysis and determination of sample size for covariance structure modeling. \emph{Psychological Methods, 1}(2), 130–149. \doi{10.1037/1082-989X.1.2.130}
}

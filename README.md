
# kfa: K-Fold Cross-Validation For Factor Analysis

[![CRAN_Status_Badge](https://www.r-pkg.org/badges/version/kfa)](https://cran.r-project.org/package=kfa)
[![metacran
downloads](https://cranlogs.r-pkg.org/badges/kfa)](https://cran.r-project.org/package=kfa)
[![metacran
downloads](https://cranlogs.r-pkg.org/badges/grand-total/kfa)](https://cran.r-project.org/package=kfa)

**kfa** provides utilities for examining the dimensionality of a set of
variables to foster scale development. Harnessing a k-fold
cross-validation approach, **kfa** helps researchers compare possible
factor structures and identify which structures are plausible and
replicable across samples.

## Installation

``` r
# From CRAN
install.packages("kfa")

# Development version
install.packages("remotes")
remotes::install_github("knickodem/kfa")

library(kfa)
```

## Workflow

The two primary functions are `kfa()` and `kfa_report()`. When the set
of potential variables and (optionally) the maximum number of factors,
*m*, are supplied to `kfa()`, the function:

-   (if requested) conducts a power analysis to determine the number of
    folds, *k*, on which to split the data into training and testing
    samples
-   creates *k* folds (i.e. the training and testing samples).

Then for each fold:

-   calculates sample statistics (e.g., correlation matrix, thresholds
    \[if necessary\]) from training sample.
-   runs `2:m` factor exploratory factor analysis (EFA) models using the
    sample statistics, applies rotation (if specified), and extracts the
    factor structure for a confirmatory factor analysis (CFA). The
    structure for a 1-factor CFA is also defined.
-   runs the `1:m` factor CFA models on the testing sample.

The factor analyses are run using the `lavaan` package with many of the
`lavaan` estimation and missing data options available for use in
`kfa()`. `kfa()` returns a list of lists with *k* outer elements for
each fold and *m* inner elements for each replicable factor model, each
containing a `lavaan` object. To expedite running *k* x *m* x 2 (EFA and
CFA) models, the function utilizes the `parallel` and `foreach` packages
for parallel processing.

``` r
library(kfa)
# simulate data based on a 3-factor model with standardized loadings
sim.mod <- "f1 =~ .7*x1 + .8*x2 + .3*x3 + .7*x4 + .6*x5 + .8*x6 + .4*x7
                f2 =~ .8*x8 + .7*x9 + .6*x10 + .5*x11 + .5*x12 + .7*x13 + .6*x14
                f3 =~ .6*x15 + .5*x16 + .9*x17 + .4*x18 + .7*x19 + .5*x20
                f1 ~~ .2*f2
                f2 ~~ .2*f3
                f1 ~~ .2*f3
                x9 ~~ .2*x10"
set.seed(1161)
sim.data <- simstandard::sim_standardized(sim.mod,
                                          n = 900,
                                          latent = FALSE,
                                          errors = FALSE)[c(2:9,1,10:20)]

# include a custom 2-factor model
custom2f <- paste0("f1 =~ ", paste(colnames(sim.data)[1:10], collapse = " + "),
                   "\nf2 =~ ",paste(colnames(sim.data)[11:20], collapse = " + "))

mods <- kfa(data = sim.data,
            k = NULL,    # NULL prompts power analysis to determine number of folds
            custom.cfas = custom2f  # can be a single object or named list
            )
```

`kfa_report()` then aggregates the CFA model fit, parameter estimates,
and model-based reliability across folds for each factor structure
extracted in `kfa()`. The results are then organized and exported via
`rmarkdown`, such as the [example
report](https://htmlpreview.github.io/?https://github.com/knickodem/kfa/blob/main/README%20Example%20Reports/example_sim_kfa_report.html)
run below.

``` r
# Run report
kfa_report(models = mods,
           file.name = "example_sim_kfa_report",
           report.title = "K-fold Factor Analysis - Example Sim",
           report.format = "html_document")
```

## Under Development and Consideration

-   **Clustered Data** - The package does not currently account for
    clustered data. Future versions will utilize the cluster argument
    from `lavaan` to estimate cluster robust standard errors when
    calculating the correlation matrix for the factor analyses. We are
    also considering how to account for nesting structures in the
    creation of the folds, which are currently created assuming a simple
    random sample. If so, we will also incorporate cluster adjustments
    for the power analysis determining the value of *k*.

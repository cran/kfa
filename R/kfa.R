#' Conducts k-fold cross validation for factor analysis.
#'
#' The function splits the data into *k* folds. For each fold,
#' EFAs are run on the training data and the simple structure for each model
#' is transformed into \code{lavaan}-compatible CFA syntax. The CFAs are then run
#' on the test data.
#'
#' @param variables a \code{data.frame} (or convertible to a \code{data.frame}) of variables (i.e., items) to factor analyze
#' @param k number of folds in which to split the data. Default is \code{NULL} which determines k via \code{\link[kfa]{find_k}}.
#' @param m integer; maximum number of factors to extract. Default is 4 items per factor.
#' @param seed integer passed to \code{set.seed} when randomly selecting cases for each fold.
#' @param cores integer; number of CPU cores to use for parallel processing. Default is \code{\link[parallel]{detectCores}} - 1.
#' @param custom.cfas a single object or named \code{list} of \code{lavaan} syntax specifying custom factor model(s).
#' @param power.args named \code{list} of arguments to pass to \code{\link[kfa]{find_k}} and \code{\link[semTools]{findRMSEAsamplesize}} when conducting power analysis to determine \code{k}.
#' @param rotation character (case-sensitive); any rotation method listed in
#' \code{\link[GPArotation]{rotations}} in the \code{GPArotation} package. Default is "oblimin".
#' @param simple logical; Should the simple structure be returned (default) when converting EFA results to CFA syntax?
#' If \code{FALSE}, items can cross-load on multiple factors.
#' @param threshold numeric between 0 and 1 indicating the minimum (absolute) value of the loading for a variable on a factor when converting EFA results to CFA syntax. Must be specified when \code{simple = FALSE}.
#' @param ordered logical; Should items be treated as ordinal and the
#' polychoric correlations used in the factor analysis? When \code{FALSE} (default)
#' the Pearson correlation matrix is used. A character vector of item names is
#' also accepted to prompt estimation of the polychoric correlation matrix.
#' @param estimator if \code{ordered = FALSE}, the default is "MLMVS". If
#' \code{ordered = TRUE}, the default is "WLSMV". See \code{\link[lavaan]{lavOptions}} for other options.
#' @param missing default is "listwise". See \code{\link[lavaan]{lavOptions}} for other options.
#' @param ... other arguments passed to \code{lavaan} functions. See \code{\link[lavaan]{lavOptions}}.
#'
#' @details
#' In order to be tested along with the EFA identified structures, each model supplied in \code{custom.cfas} must
#' include all \code{variables} in \code{lavaan} compatible syntax. To test a model when dropping
#' a variable, have the variable load on to one factor while constraining the loading to 0.
#'
#' Deciding an appropriate *m* can be difficult, but is consequential for both the possible factor structures to
#' examine and the computation time. The \code{n_factors} in the \code{parameters} package
#' can assist with this decision.
#'
#' @return An object of class \code{"kfa"}, which is a four-element \code{list}:
#' \itemize{
#' \item **cfas** \code{lavaan} CFA objects for each *k* fold
#' \item **cfa.syntax** syntax used to produce CFA objects
#' \item **model.names** vector of names for CFA objects
#' \item **efa.structures** all factor structures identified in the EFA
#' }
#'
#' @examples
#'
#' # simulate data based on a 3-factor model with standardized loadings
#' sim.mod <- "f1 =~ .7*x1 + .8*x2 + .3*x3 + .7*x4 + .6*x5 + .8*x6 + .4*x7
#'                 f2 =~ .8*x8 + .7*x9 + .6*x10 + .5*x11 + .5*x12 + .7*x13 + .6*x14
#'                 f3 =~ .6*x15 + .5*x16 + .9*x17 + .4*x18 + .7*x19 + .5*x20
#'                 f1 ~~ .2*f2
#'                 f2 ~~ .2*f3
#'                 f1 ~~ .2*f3
#'                 x9 ~~ .2*x10"
#' set.seed(1161)
#' sim.data <- simstandard::sim_standardized(sim.mod, n = 900,
#'                                           latent = FALSE,
#'                                           errors = FALSE)[c(2:9,1,10:20)]
#'
#' # include a custom 2-factor model
#' custom2f <- paste0("f1 =~ ", paste(colnames(sim.data)[1:10], collapse = " + "),
#'                    "\nf2 =~ ",paste(colnames(sim.data)[11:20], collapse = " + "))
#'
#' \donttest{
#' mods <- kfa(variables = sim.data,
#'             k = NULL, # prompts power analysis to determine number of folds
#'             cores = 2,
#'             custom.cfas = custom2f)
#'             }
#'
#' @import foreach
#' @importFrom caret createFolds
#' @importFrom doParallel registerDoParallel
#' @importFrom doParallel stopImplicitCluster
#' @importFrom parallel detectCores
#' @importFrom parallel makeCluster
#' @importFrom parallel stopCluster
#' @importFrom simstandard sim_standardized
#'
#' @export
#' @md

kfa <- function(variables,
                k = NULL,
                m = floor(ncol(variables) / 4),
                seed = 101, cores = NULL,
                custom.cfas = NULL,
                power.args = list(rmsea0 = .05, rmseaA = .08),
                rotation = "oblimin", simple = TRUE, threshold = NA,
                ordered = FALSE, estimator = NULL, missing = "listwise", ...){

  variables <- as.data.frame(variables)

  # The ordered = TRUE functionality not available in lavCor (i.e., not currently equivalent to listing
  # all items), so need to do it manually since I want this functionality for our users
  if(is.logical(ordered)){
    if(ordered == FALSE){
      ordered <- NULL
      if(is.null(estimator)){
        estimator <- "MLMVS"
      }
    } else if(ordered == TRUE){
      ordered <- names(variables)
      if(is.null(estimator)){
        estimator <- "WLSMV"
      }
    }
  } else if(is.character(ordered)){
    if(is.null(estimator)){
      estimator <- "WLSMV"
    }
  }

  ## cross-loading check
  if(simple == FALSE & is.na(threshold)){
    stop("threshold must be supplied when simple = FALSE")
  }

  # # Not used at the moment
  # lavaan.args <- c(list(rotation = rotation, ordered = ordered,
  #                       estimator = estimator, missing = missing, list(...)))

  if(is.null(k)){
    ## determine number of folds based on power analysis
    fk <- do.call(find_k, c(list(variables = variables, m = m), power.args))
    k <- fk[[1]]
  }

  # if(k < 2 | k > 10){
  #   stop('k must be > 1 and < 11')
  # }

  set.seed(seed)

  ## create folds
  if(k == 0){
    testfolds <- list(Fold1 = 0)
    k <- 1
  } else {

    # returns list of row numbers for each test fold (i.e., the cfa sample)
    # contents of y doesn't matter, just needs to be nrow(variables) in length
    testfolds <- caret::createFolds(y = 1:nrow(variables),
                                    k = k, list = TRUE,
                                    returnTrain = FALSE)
    if(length(testfolds[[1]]) < 200){
      warning("Sample size for each test fold is ", length(testfolds[[1]]), ",\nwhich is smaller than the recommended 200 (Curran, Bollen, Chen, Paxton, & Kirby, 2003)")
    }
  }

  if(.Platform$OS.type == "windows"){
    cluster.type <- "PSOCK"
  } else{
    cluster.type <- "FORK"
  }

  tryCatch(  # used to stop the parallelization regardless of whether kfa runs successfully or breaks
    expr = {

      cores <- if(is.null(cores)|!is.numeric(cores)) parallel::detectCores() - 1 else cores
      clusters <- parallel::makeCluster(cores, type = cluster.type)
      doParallel::registerDoParallel(clusters)

      print(paste("Using", foreach::getDoParWorkers(), "cores for parallelization."))

      ## run EFAs and return lavaan syntax for CFAs
      fold <- NULL # need this for CRAN check
      efa <- foreach::foreach(fold = 1:k) %dopar% { # use %do% if we offer a parallel = FALSE option

        k_efa(variables = variables[!c(row.names(variables) %in% testfolds[[fold]]), ],
              m = m,
              rotation = rotation,
              simple = simple,
              threshold = threshold,
              ordered = ordered,
              estimator = estimator,
              missing = missing,
              ...)

        ## do.call version throws error for some reason ( Error in { : task 1 failed - "$ operator is invalid for atomic vectors" )
        # do.call(k_efa, args = c(list(variables = variables[!c(row.names(variables) %in% testfolds[[fold]]), ],
        #                              m = m),
        #                         lavaan.args))
      }

      ## identifying unique structures
      efa.structures <- model_structure_efa(efa)
      names(efa.structures) <- paste0(1:m, "-factor")

      ## collect most common (mode) structure for each factor model to use in CFAs
      mode.structure <- rep(list(rep(list(""), m)), k) # creates list of lists framework needed for running cfas
      for(n in 1:m){  # replaces "" in the sublists with mode structure when appropriate given the values in x$folds
        if(length(efa.structures[[n]]) == 1){ # if there is only 1 structure of a given model
          for(i in efa.structures[[n]][[1]]$folds){
            mode.structure[[i]][[n]] <- efa.structures[[n]][[1]]$structure
          }
        } else {
          # number of folds each structure was found; keep most common structure
          num.folds <- unlist(lapply(efa.structures[[n]], function(x) length(x$folds)))
          ties <- which(num.folds == max(num.folds))
          ties <- ifelse(length(ties) == 1, ties, ties[[1]]) # in case of ties, use first structure
          for(i in efa.structures[[n]][[ties]]$folds){
            mode.structure[[i]][[n]] <- efa.structures[[n]][[ties]]$structure
          }
        }
      }

      ## add names to models for each fold
      mode.structure <- lapply(mode.structure, function(x) {
        names(x) <- paste0(1:m, "-factor")
        return(x)
      })

      ## add custom models (if present)
      if(!is.null(custom.cfas)){
        if(class(custom.cfas) != "list"){ # converting single object to named list
          custom.name <- deparse(substitute(custom.cfas))
          custom.cfas <- list(custom.cfas)
          names(custom.cfas) <- custom.name
        } else if(is.null(names(custom.cfas))){ # (if necessary) adding names to list
          names(custom.cfas) <- paste("custom", LETTERS[1:length(custom.cfas)])
        }
        # add custom models to set of models for each fold
        cfa.syntax <- lapply(mode.structure, function(x) c(x, custom.cfas))
      } else {
        cfa.syntax <- mode.structure
      }

      if(k == 1 & length(testfolds$Fold1) == 1){
        testfolds$Fold1 <- 1:nrow(variables)
      }

      ## run CFAs
      cfas <- foreach::foreach(fold = 1:k) %dopar% {

        k_cfa(syntax = cfa.syntax[[fold]],
              variables = variables[testfolds[[fold]], ],
              ordered = ordered,
              estimator = estimator,
              missing = missing,
              ...)

        # do.call(k_cfa, args = c(list(syntax = cfa.syntax[[fold]],
        #                              variables = variables[testfolds[[fold]], ]),
        #                         lavaan.args))
      }

      ## gathering model names
      mnames <- names(cfa.syntax[[1]])
      empty <- vector("list", k)
      for(f in 1:k){
        empty[[f]] <- unlist(lapply(cfa.syntax[[f]], function(x) x == ""))
      }

      if(k > 1){
        drop <- colSums(Reduce("rbind", empty)) == k
      } else {
        drop <- empty[[1]]
      }
      mnames <- mnames[!drop]

      ## organizing output
      output <- list(cfas = cfas,
                     cfa.syntax = cfa.syntax,
                     model.names = mnames,
                     efa.structures = efa.structures)
    },
    finally = {
      parallel::stopCluster(clusters)
    })

  class(output) <- "kfa"

  return(output)
}

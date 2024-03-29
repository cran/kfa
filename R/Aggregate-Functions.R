#' Aggregated factor loadings
#'
#' The factor loadings aggregated over k-folds
#'
#' @param models An object returned from \code{\link[kfa]{kfa}}
#' @param flag threshold below which loading will be flagged
#' @param digits integer; number of decimal places to display in the report.
#'
#' @return \code{data.frame} of mean factor loadings for each factor model and \code{vector} with count of folds with a flagged loading
#'
#' @examples
#' data(example.kfa)
#' agg_loadings(example.kfa)
#'
#' @import lavaan
#' @export

agg_loadings <- function(models, flag = .30, digits = 2){

  if(inherits(models, "kfa")){
    cfas <- models$cfas
  } else {
    stop("models must be of class 'kfa'.")
  }

  vnames <- dimnames(lavaan::lavInspect(cfas[[1]][[1]], "sampstat")$cov)[[1]] # variable names
  mnames <- models$model.names # model names
  m <- length(mnames) #max(unlist(lapply(cfas, length))) # maximum number of models per fold
  k <- length(cfas) # number of folds

  klambdas <- vector("list", m)  # factor loadings across folds
  names(klambdas) <- mnames
  lflag <- vector("integer", m)  # low loading flag
  names(lflag) <- mnames
  hflag <- vector("integer", m)  # heywood case flag
  names(hflag) <- mnames

  for(n in mnames){
    lambdas <- vector("list", k)
    thetas <- vector("list", k)
    load.flag <- vector("integer", k)
    hey.flag <- vector("integer", k)
    for(f in 1:k){
      if(n %in% names(cfas[[f]])){
        ## gather standardized loadings
        l.temp <- lavaan::standardizedSolution(cfas[[f]][[n]], "std.all", se = FALSE)
        lambdas[[f]] <- l.temp[l.temp$op == "=~",]

        # flag for model summary table
        load.flag[[f]] <- sum(abs(lambdas[[f]]$est.std) < flag)

        ## gather residual variances
        t.temp <- lavaan::parameterestimates(cfas[[f]][[n]], se = FALSE)
        thetas[[f]] <- t.temp[t.temp$op == "~~" & t.temp$lhs %in% vnames & t.temp$lhs == t.temp$rhs,]

        # flag for model summary table
        hey.flag[[f]] <- sum(thetas[[f]]$est < 0)
      }
    }
    lambdas <- do.call("rbind", lambdas)
    thetas <- do.call("rbind", thetas)

    # identifying cross-loading items
    byfactor <- tapply(lambdas$est.std, INDEX = list(lambdas$lhs, lambdas$rhs), sum) # most any function will do; we do not use the value in the cells, only care if NA
    cls <- names(which(apply(byfactor, 2, function(x) sum(!is.na(x)) > 1))) # cross-loading variables

    if(length(cls) > 0){ # only search for cross-loading secondary factor if needed

      # is.na(lambdas$est.std) <- !lambdas$est.std # converts 0 to NA; don't need to do this though b/c the variable would be constrained in all folds
      lambdas$f.v <- paste(lambdas$lhs, lambdas$op, lambdas$rhs) # adds column of factor by variable strings

      fv.means <- tapply(lambdas$est.std, lambdas$f.v, mean) # mean loading for each factor-variable pair
      ord <- lapply(cls, function(x) sort(fv.means[grepl(x, names(fv.means))], decreasing = TRUE)) # ordering means
      p <- unlist(lapply(ord, function(x) names(x)[[1]])) # extracting primary factor
      s <- unlist(lapply(ord, function(x) names(x)[[2]])) # extracting secondary factor
      # need both p and s in case there are tertiary cross-loadings, which we will not report

      primary <- lambdas[!lambdas$rhs %in% cls | lambdas$f.v %in% p,]
      secondary <- lambdas[lambdas$f.v %in% s,]


      primary.df <- data.frame(mean = tapply(primary$est.std, primary$rhs, mean),
                               range = paste(format(round(tapply(primary$est.std, primary$rhs, min), digits = digits), nsmall = digits), "-",
                                             format(round(tapply(primary$est.std, primary$rhs, max), digits = digits), nsmall = digits)),
                               `loading flag` = tapply(primary$est.std, primary$rhs, function(x) sum(abs(x) < flag)),
                               `heywood flag` = tapply(thetas$est, thetas$rhs, function(x) sum(x < 0)),
                               check.names = FALSE)
      primary.df <- cbind(data.frame(variable = row.names(primary.df)), primary.df)

      # note: secondary does not have heywood flag b/c that is a variable level indicator, not variable by factor level indicator
      secondary.df <- data.frame(mean.s = tapply(secondary$est.std, secondary$rhs, mean),
                                 range.s = paste(format(round(tapply(secondary$est.std, secondary$rhs, min), digits = digits), nsmall = digits), "-",
                                                 format(round(tapply(secondary$est.std, secondary$rhs, max), digits = digits), nsmall = digits)),
                                 `loading flag.s` = tapply(secondary$est.std, secondary$rhs, function(x) sum(x < flag)),
                                 check.names = FALSE)
      secondary.df <- cbind(data.frame(variable = row.names(secondary.df)), secondary.df)

      kl <- merge(primary.df, secondary.df, by = "variable", all = TRUE, sort = FALSE) # sorting has to happen in next lines
      kl$variable <- factor(kl$variable, levels = vnames)
      # row.names(kl) <- NULL
      klambdas[[n]] <- kl[order(kl$variable),]

    } else {

      kl <- data.frame(mean = tapply(lambdas$est.std, lambdas$rhs, mean),
                       range = paste(format(round(tapply(lambdas$est.std, lambdas$rhs, min), digits = digits), nsmall = digits), "-",
                                     format(round(tapply(lambdas$est.std, lambdas$rhs, max), digits = digits), nsmall = digits)),
                       `loading flag` = tapply(lambdas$est.std, lambdas$rhs, function(x) sum(abs(x) < flag)),
                       `heywood flag` = tapply(thetas$est, thetas$rhs, function(x) sum(x < 0)),
                       check.names = FALSE)
      # order dataframe by vnames
      kl <- cbind(data.frame(variable = factor(row.names(kl), levels = vnames)), kl)
      klambdas[[n]] <- kl[order(kl$variable),]
    }

    ## count of folds with a loading under flag threshold
    lflag[[n]] <- sum(load.flag > 0)
    hflag[[n]] <- sum(hey.flag > 0)
  }

  return(list(loadings = klambdas,
              flag = lflag,
              heywood = hflag))
}


#' Aggregated factor correlations
#'
#' The factor correlations aggregated over k-folds
#'
#' @param models An object returned from \code{\link[kfa]{kfa}}
#' @param flag threshold above which a factor correlation will be flagged
#' @param type currently ignored; \code{"factor"} (default) or \code{"observed"} variable correlations
#'
#' @return \code{data.frame} of mean factor correlations for each factor model and \code{vector} with count of folds with a flagged correlation
#'
#' @examples
#' data(example.kfa)
#' agg_cors(example.kfa)
#'
#' @export

agg_cors <- function(models, flag = .90, type = "factor"){

  if(inherits(models, "kfa")){
    cfas <- models$cfas
  } else {
    stop("models must be of class 'kfa'.")
  }
  mnames <- models$model.names # model names
  m <- length(mnames)
  k <- length(cfas)


  kcorrs <- vector("list", m)
  names(kcorrs) <- mnames
  kflag <- vector("integer", m)
  names(kflag) <- mnames

  # Currently assumes the first element is a 1 factor model; need a more robust check
  kflag[[1]] <- NA
  if(m > 1){
    for(n in 2:m){
      cor.lv <- vector("list", k) # latent variable correlation matrix
      cor.flag <- vector("list", k) # count of correlations above flag threshold
      for(f in 1:k){
        if(mnames[[n]] %in% names(cfas[[f]])){
          cor.lv[[f]] <- lavaan::lavInspect(cfas[[f]][[mnames[[n]]]], "cor.lv")
          cor.flag[[f]] <- rowSums(cor.lv[[f]] > flag) - 1 # minus diagonal which will always be TRUE
        }
      }

      ## count of folds with a correlation over flag threshold
      fc <- unlist(cor.flag)
      cflag <- tapply(fc, names(fc), function(x) sum(x > 0)) # for each factor
      kflag[[n]] <- sum(unlist(lapply(cor.flag, sum)) > 0)      # for the model

      ## mean correlation across folds
      cor.lv <- cor.lv[lengths(cor.lv) != 0] # removes NULL elements for folds were model was not run
      aggcorrs <- Reduce(`+`, lapply(cor.lv, r2z)) / length(cor.lv) # pool results after Fisher's r to z
      aggcorrs <- z2r(aggcorrs)
      diag(aggcorrs) <- 1       # change diagonals from NaN to 1
      aggcorrs[upper.tri(aggcorrs, diag = FALSE)] <- NA
      aggcorrs <- cbind(data.frame(rn = row.names(aggcorrs)), aggcorrs)
      # cflag names are alphabetical, rather than original factor order so must merge with sort = F
      aggcorrs <- merge(aggcorrs, data.frame(rn = names(cflag), flag = cflag),
                        by = "rn", all = TRUE, sort = FALSE)
      kcorrs[[n]] <- aggcorrs
    }
  }


  return(list(correlations = kcorrs,
              flag = kflag))
}

#' Fisher's r to z transformation
#'
#' @param r correlation
#'
#' @return z-score
#'
#' @noRd

r2z <- function(r){
  0.5 * log((1 + r)/(1 - r))
}

#' Fisher's z to r transformation
#'
#' @param z z-score
#'
#' @return correlation
#'
#' @noRd

z2r <- function(z){
  (exp(2 * z) - 1)/(1 + exp(2 * z))
}

#' Aggregated scale reliabilities
#'
#' The factor reliabilities aggregated over k-folds
#'
#' @param models An object returned from \code{\link[kfa]{kfa}}
#' @param flag threshold below which reliability will be flagged
#' @param digits integer; number of decimal places to display in the report.
#'
#' @return \code{data.frame} of mean factor (scale) reliabilities for each factor model and \code{vector} with count of folds with a flagged reliability
#'
#' @examples
#' data(example.kfa)
#' agg_rels(example.kfa)
#'
#' @export

agg_rels <- function(models, flag = .60, digits = 2){

  if(inherits(models, "kfa")){
    cfas <- models$cfas
  } else {
    stop("models must be of class 'kfa'.")
  }
  mnames <- models$model.names # model names
  m <- length(mnames) #max(unlist(lapply(cfas, length))) # maximum number of models per fold
  k <- length(cfas) # number of folds

  # semTools::reliability does not currently calculate alpha from summary stats with categorical indicators
  what <- if(lavaan::lavInspect(cfas[[1]][[1]], "categorical")) "omega3" else c("omega3", "alpha")

  krels <- vector("list", m)
  names(krels) <- mnames
  kflag <- vector("integer", m)
  names(kflag) <- mnames
  for(n in 1:m){
    rels <- vector("list", k)
    rel.flag <- vector("integer", k)
    for(f in 1:k){
      if(mnames[[n]] %in% names(cfas[[f]])){
        rels[[f]] <- t(suppressMessages(semTools::reliability(cfas[[f]][[mnames[[n]]]], what = what)))
        rel.flag[[f]] <- sum(rels[[f]][,"omega3"] < flag) # flag based on omega, not alpha
      }
    }

    ## mean reliability across folds
    aos <- do.call("rbind", rels)
    if(n == 1){
      fn <- "f1"
      fnames <- rep(fn, nrow(aos))
    } else{
      rels <- rels[lengths(rels) != 0] # removes NULL elements for folds were model was not run
      fn <- dimnames(rels[[1]])[[1]]  # grabs unique factor names from first fold; should be the same in all folds
      fnames <- dimnames(aos)[[1]] # should be the equivalent of rep(fn, nrow(aos))
    }

    rdf <- data.frame(factor = sort(fn)) # need to use sort b/c that is the order tapply will output
    for(w in 1:length(what)){
      test <- data.frame(mean = tapply(aos[, w], fnames, mean),
                         range = paste(format(round(tapply(aos[, w], fnames, min), digits = digits), nsmall = digits), "-",
                                       format(round(tapply(aos[, w], fnames, max), digits = digits), nsmall = digits)),
                         flag = tapply(aos[, w], fnames, function(x) sum(x < flag)))
      names(test) <- paste(what[[w]], names(test), sep = ".")
      rdf <- cbind(rdf, test)

    }
    rdf$factor <- factor(rdf$factor, levels = fn)
    krels[[n]] <- rdf[order(rdf$factor),]

    ## count of folds with a reliabilities below flag threshold
    kflag[[n]] <- sum(rel.flag > 0)
  }

  return(list(reliabilities = krels,
              flag = kflag))
}

#' Flag model problems
#'
#' Internal function to create table of flag counts
#'
#' @param models An object returned from \code{\link[kfa]{kfa}}
#' @param strux An object returned from \code{\link[kfa]{model_structure}}
#' @param loads An object returned from \code{\link[kfa]{agg_loadings}}
#' @param cors An object returned from \code{\link[kfa]{agg_cors}}
#' @param rels An object returned from \code{\link[kfa]{agg_rels}}
#'
#' @return a \code{data.frame}
#'
#' @noRd

model_flags <- function(models, strux, loads, cors, rels){

  # Multiple structures from EFA
  strux <- strux[c("model", "folds")]
  names(strux) <- c("model", "mode structure")

  # flags from CFA models
  cfas <- models$cfas
  k <- length(cfas)
  m <- max(unlist(lapply(cfas, length)))

  ## Flagging non-convergence and non-positive definite matrix warnings
  cnvgd <- vector("list", k)
  hey <- vector("list", k)
  for(f in 1:k){

    ## convergence status of each model
    cnvgd[[f]] <- lapply(cfas[[f]], lavaan::lavInspect, "converged")
    ## presence of non-positive definite matrix (and heywood cases) in each model
    hey[[f]] <- lapply(cfas[[f]], lavaan::lavInspect, "post.check")

  }

  # flagged if either indicates an improper solution
  temp <- c(unlist(cnvgd) == FALSE, unlist(hey) == FALSE)
  improper <-tapply(temp, names(temp), sum) # orders output alphabetically
  # adjust order to match model.names and other flags
  improper <- improper[order(factor(names(improper), levels=models$model.names))]

  ## joining flags into data.frame
  flags <- data.frame(model = models$model.names,
                      `improper solution` = improper,
                      `heywood item` = loads$heywood,
                      `low loading` = loads$flag,
                      `high factor correlation` = cors$flag,
                      `low scale reliability` = rels$flag,
                      check.names = FALSE)

  flags <- merge(strux, flags, by = "model", all.x = FALSE, all.y = TRUE, sort = FALSE)

  return(flags)
}


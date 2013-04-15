#' GEE helper function
#'
#' @title GEE helper 2
#'
#' @param formula
#' @param family
#' @param link 
#' @param data
#' @param cluster
#' @param alpha
#' @param phi
#' @param corstr
#' @param start.betas
#' @param zcor
#' @export
#'
gee.beta.ds <- function(formula, family, link, data, cluster, alpha, phi, corstr, start.betas=NULL, zcor=NULL){
  
  input.table <- data
  id <- cluster
  
  cluster.id.indx <- 0
  for(i in 1:dim(input.table)[2]){
    comp <- input.table[,i] == id
    cluster.id.indx <- i
    if(mean(comp, na.rm=TRUE) == 1){
      break
    }
  }
  form4nlme <- as.formula(paste("~ 1 | ", colnames(input.table)[cluster.id.indx], sep=""))
  
  corr.strc <- function (int) {
    if(int == 1){
      "ar1"
    }else if(int == 2){
      "exchangeable"
    } else if(int == 3){
      "independence"
    }else if(int == 4){
      "fixed"
    }else if(int == 5){
      "unstructured"
    }
  }
  
  corstr <- corr.strc(corstr)
  
  link.func <- function (int) {
    if(int == 1){
      "logit"
    }else if(int == 2){
      "identity"
    } else if(int == 3){
      "inverse"
    }else if(int == 4){
      "log"
    }else if(int == 5){
      "probit"
    }
  }
  
  linkf <- link.func(link)
  
  if(is.function(family)) {
    family <- family(linkf)
  }
  
  # THESE TWO LINES GET THE 'X' and "Y" WE WERE GETTING THROUGH ONE the geeglm FUNCTION OF 'GEEPACK'
  frame <- model.frame(formula, data)
  X.mat <- model.matrix(formula, frame)
  y.vect <- as.vector(model.response(frame, type="numeric"))
  
  # SET THE BETA VALUES TO 0 IF THEY WERE NOT SPECIFIED
  if(is.null(start.betas)) {
    start.betas <- rep(0,dim(X.mat)[2])
  }
  
  # NUMBER OF BETA PARAMETERS 
  npara <- dim(X.mat)[2]
  
  # NUMBER OF OBSERVATIONS (SUBJECTS)
  N <- length(id)
  
  # GET LAGGED AND ITERATED DIFFERENCES OF THE VECTOR IDs (BY DEFAULT'LAG'=1 AND 'ORDER OF DIFFERENCE' = 1)
  clusnew <- c(which(diff(as.numeric(id)) != 0), length(id))
  clusz <- c(clusnew[1], diff(clusnew))
  
  # NUMBER OF CLUSTERS (i.e. NUMBER OF SUBJECTS)
  N.clus <- length(clusz)
  
  # ESTIMATED RESPONSE
  lp.vect <- X.mat%*%start.betas
  
  # VALUES FOR THE INVERSE LINK FUNCTION AND THE RELATED MEAN AND VARIANCE
  f <- family
  mu.vect <- f$linkinv(lp.vect)
  var.vect <- f$variance(mu.vect)
  
  # LOAD THE 'nlme' PACKAGE TO USE FUNCTIONS TO CREATE CORRELATION STRUCTURES
  library("nlme")
  
  # MATRIX IF THE CORRELATION STRUCTURE IS 'AUTOREGRESSIVE AR (1)'
  if(corstr == "ar1"){
    # THE ORDER OF THE OBSERVATIONS WITHIN A GROUP IS USED AS POSITION VARIABLE 
    # (THE FIRST ARGUMENT OF THE 'FORM' PARAMETER) AND THE IDS ARE USED AS GROUPING PARAMETER 
    R.mat.AR1 <- corAR1(alpha, form = form4nlme)
    R.mat.AR1.i <- Initialize(R.mat.AR1, data=input.table)
    list.of.matrices <- corMatrix(R.mat.AR1.i)
  }
  
  # MATRIX IF THE CORRELATION STRUCTURE IS 'EXCHANGEABLE'
  if(corstr == "exchangeable"){
    R.mat.EXCH <- corCompSymm(alpha, form = form4nlme)
    R.mat.EXCH.i <- Initialize(R.mat.EXCH, data=input.table)
    list.of.matrices <- corMatrix(R.mat.EXCH.i)
  }
  
  # MATRIX IF THE CORRELATION STRUCTURE IS 'INDEPENDENT'
  if(corstr == "independence"){
    R.mat.INDP <- corCompSymm(0, form = form4nlme)
    R.mat.INDP.i <- Initialize(R.mat.INDP, data=input.table)
    list.of.matrices <- corMatrix(R.mat.INDP.i)
    
  }
  
  # MATRIX IF THE CORRELATION STRUCTURE IS 'UNSTRUCTERED'
  if(corstr == "unstructured"){
    mt.temp <- matrix(0, nrow=max(table(id)), ncol=max(table(id)))
    num.alpha.vals <- length(mt.temp[col(mt.temp) < row(mt.temp)])
    R.mat.unstr <- corSymm(alpha[1:num.alpha.vals], form = form4nlme)
    R.mat.unstr.i <- Initialize(R.mat.unstr, data=input.table)
    list.of.matrices <- corMatrix(R.mat.unstr.i)
  }
  
  # MATRIX IF THE CORRELATION STRUCTURE IS 'FIXED' (USER DEFINED)
  if(corstr == "fixed"){
    # DISPLAY A MEESAGE AND STOP PROCESS IF NO USER DEFINED COR MATRIX HAVE BEEN SUPPLIED
    if(is.null(zcor)){
      stop(call.=FALSE, "\n NO USER DEFINED CORRELATION 	STRUCTURE SUPPLIED!\n")
    }
    low.diag.elts <- zcor[col(zcor) < row(zcor)]
    R.mat.userdef <- corSymm(low.diag.elts, form = form4nlme)
    R.mat.userdef.i <- Initialize(R.mat.userdef, data=input.table)
    list.of.matrices <- corMatrix(R.mat.userdef.i)
  }
  
  # assign working correlation matrices (one per cluster/family)
  R.mat <- list.of.matrices
  
  # get the largest of the working correlation matrices (matrix with the largest diagonal)
  diag.length <- rep(0, length(R.mat))
  for(i in 1:length(R.mat)){
    diagonal <- diag(R.mat[[i]])
    diag.length[i] <- length(diagonal)
  }
  diag.indx <- which(diag.length == max(diag.length, na.rm=TRUE))
  # there might more than one matrix that has the longuest diagonal, pick the first one
  work.cor.mat <- R.mat[[diag.indx[1]]]
  
  # CREATING THE A MATRIX (LIANG AND ZEGER)
  A.mat <- vector("list", N.clus)
  A.mat[[1]] <- phi^(-1)*diag(var.vect[1:clusnew[1]])
  for(i in 2:N.clus){
    A.mat[[i]] <- phi^(-1)*diag(var.vect[(clusnew[i-1]+1):clusnew[i]]) 
  }
  
  # CREATING THE V MATRIX - ESTIMATE OF THE WORKING CORRELATION MATRIX (LIANG AND ZEGER)
  V.mat <- vector("list", N.clus)
  for(i in 1:N.clus){
    V.mat[[i]] <- phi*(sqrt(A.mat[[i]])%*%R.mat[[i]]%*%sqrt(A.mat[[i]]))  
  }
  
  # FAMILY-SPECIFIC FUNCTIONS TO HELP CALCULATE BETA
  deriv.vect <- f$mu.eta(lp.vect)
  
  if(f$family=="gaussian"){
    der.vect <- rep(1,N)
  }
  
  if(f$family=="poisson") {
    der.vect <- mu.vect^(-1)
  }
  
  if(f$family=="binomial"){
    der.vect <- 1/(mu.vect*(1-mu.vect))
  }
  
  if(f$family=="Gamma"){
    der.vect <- 1/(mu.vect^2)
  }
  
  if(f$family=="inverse.gaussian"){
    der.vect <- 1/(mu.vect^3)
  }
  
  # DELTA MATRIX, LIANG AND ZEGER. THIS IS AN IDENTITY MATRIX IF USING CANONICAL LINK FOR A FAMILY
  Delta.vec<-deriv.vect*der.vect
  Delta.mat<-vector("list",N.clus)
  Delta.mat[[1]] <- diag(Delta.vec[1:clusnew[1]])
  for(i in 2:N.clus){
    Delta.mat[[i]] <- diag(Delta.vec[(clusnew[i-1]+1):clusnew[i]])
  }
  
  # D MATRIX OF PARTIAL DERIVATIVES, LIANG AND ZEGER
  D.mat <- vector("list", N.clus)
  D.mat[[1]] <- t(A.mat[[1]])%*%Delta.mat[[1]]%*%X.mat[1:clusnew[1],]
  for(i in 2:N.clus){
    D.mat[[i]] <- t(A.mat[[i]])%*%Delta.mat[[i]]%*%X.mat[ (clusnew[i-1]+1):clusnew[i],]
  }
  
  # CALULATING ALL CLUSTER-SPECIFIC INFORMATION MATRICES 
  I.mat<-vector("list", N.clus)
  for(i in 1:N.clus){
    I.mat[[i]] <- t(D.mat[[i]])%*%solve(V.mat[[i]])%*%D.mat[[i]]
  }
  
  # SUMMING ALL CLUSTER-SPECIFIC INFORMATION MATRICES
  infomatrix <- matrix(rep(0,npara^2), ncol=npara)
  for (i in 1:N.clus){
    infomatrix <- infomatrix+I.mat[[i]]
  }
  
  # CALULATING ALL CLUSTER-SPECIFIC SCORE VECTORS
  s.vec <- vector("list", N.clus)
  s.vec[[1]] <- t(D.mat[[1]])%*%solve(V.mat[[1]])%*%(y.vect[1:clusnew[1]]-mu.vect[1:clusnew[1]])
  for(i in 2:N.clus){
    s.vec[[i]] <- t(D.mat[[i]])%*%solve(V.mat[[i]])%*%(y.vect[(clusnew[i-1]+1):clusnew[i]]-mu.vect[(clusnew[i-1]+1):clusnew[i]])
  }
  
  # SUMMING ALL CLUSTER-SPECIFIC SCORE VECTORS
  score <- c(rep(0, npara))
  for (i in 1:N.clus){
    score <- score+s.vec[[i]]
  }
  # J.matrices needed to calculate standard error of estimates
  J1 <- vector("list", N.clus)
  
  J1[[1]] <- t(D.mat[[1]])%*%solve(V.mat[[1]])%*%(y.vect[1:clusnew[1]]-mu.vect[1:clusnew[1]])%*%t(y.vect[1:clusnew[1]]-mu.vect[1:clusnew[1]])%*%solve(V.mat[[1]])%*%D.mat[[1]]
  for(i in 2:N.clus){
    
    J1[[i]] <- t(D.mat[[i]])%*%solve(V.mat[[i]])%*%(y.vect[(clusnew[i-1]+1):clusnew[i]]-
                                                      mu.vect[(clusnew[i-1]+1):clusnew[i]])%*%t(y.vect[(clusnew[i-1]+1):clusnew[i]]
                                                                                                -mu.vect[(clusnew[i-1]+1):clusnew[i]])%*%solve(V.mat[[i]])%*%D.mat[[i]]
  }
  J.matrix <- matrix(rep(0,npara^2), ncol=npara)
  
  for (i in 1:N.clus){
    
    J.matrix <- J.matrix + J1[[i]]
    
  }
  
  # OUTPUT
  
  list(score.vector=score, info.matrix=infomatrix, J.matrix=J.matrix, working.cor.matrix= work.cor.mat)   
}
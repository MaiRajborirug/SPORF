#' Packs a forest and saves modified forest to disk for use by PackPredict function
#'
#' Efficiently packs a forest trained with the RF option.  Two intermediate data structures are written to disk, forestPackTempFile.csv and traversalPackTempFile.csv.  The size of these data structures is proportional to a trained forest and training data respectively.  Both data structures are removed at the end of the operation.  The resulting forest is saved as forest.out.  The size of this file is similar to the size of the trained forest.
#'
#' @param X an n by d numeric matrix (preferable) or data frame used to train the forest. 
#' @param Y a numeric vector of size n.  If the Y vector used to train the forest was not of type numeric then a simple call to as.numeric(Y) will suffice as input.
#' @param csvFileName the name of a headerless csv file containing combined data and labels.
#' @param columnWithY is the column in the headerless csv file containing class lables.
#' @param maxDepth int the maximum allowed tree height/depth (path distance between root and leaves). (maxDepth = Inf, i.e. largest system int)
#' @param minParent is the size of nodes that will not be split (minParent=1)
#' @param numTreesInForest the number of trees to grow in the forest (numTreesInForest=500)
#' @param numCores is the number of cores to use when training and predicting with the forest (numCores=1)
#' @param numTreeBins the number of bins to store the forest.  Each bin will contain numTreesInForest/numTreeBins trees.  Only used when forestType=="binned*" (numTreeBins= numCores)
#' @param NodeSizeToBin the minimum node size to use stratified subsampling (NodeSizeToBin=NULL)
#' @param NodeSizeBin the size of the stratified subsample chosen when NodeSizeToBin criteria is met (NodeSizeBin=NULL)
#' @param forestType the type of forest to grow:
#' \itemize{
#'		\item rfBase: The RF algorithm.
#'		\item rerf: The Randomer Forest algorithm.
#'		\item binnedBaseRerF: Randomer Forest with forest packing and projection weights sampled from {0,1}.
#'		\item binnedBase: RF with forest packing.
#'		\item binnedBaseTern: Randomer Forest with forest packing and projection weights sampled from {-1,0,1}.
#'		\item S-RerF: The Structured Randomer Forest algorithm (for 2d
#'		images) with forest packing, weight = 1.
#' }
#' @param mtry the number of features to consider when splitting a node (mtry=ncol(X)^.5)
#' @param mtryMult the average number of features combined to form a new feature when using RerF (mtryMult=1)
#' @param imageHeight int for use in Structured-RerF. (NULL)
#' @param imageWidth int for use in Structured-RerF. (NULL)
#' @param patchHeightMax int  for use in Structured-RerF. (NULL)
#' @param patchHeightMin int for use in Structured-RerF. (NULL)
#' @param patchWidthMax int for use in Structured-RerF. (NULL)
#' @param patchWidthMin int for use in Structured-RerF. (NULL)
#'
#'
#' @export
#'
#' @examples
#' library(rerf)
#' ## setup data
#' X <- as.matrix(iris[, 1:4])
#' Y <- as.numeric(iris[[5]]) - 1
#' forest <- fpRerF(X, Y, numCores = 2L)
#' (training.error <- mean(fpPredict(forest, X) != Y))
#'


fpRerF <-
	function(X=NULL, Y=NULL,csvFileName=NULL, columnWithY=NULL, maxDepth = Inf, minParent=1, numTreesInForest=500, numCores=1,numTreeBins=NULL, forestType="binnedBaseRerF", nodeSizeToBin=NULL, nodeSizeBin=NULL,mtry=NULL, mtryMult=NULL,seed=sample(1:1000000,1), imageHeight = NULL, imageWidth = NULL, patchHeightMax = imageHeight, patchHeightMin = 1, patchWidthMax = imageWidth, patchWidthMin = 1){

		##### Basic Checks
		################################################
		if(numCores < 1){
			stop("at least one core must be used.")
		}
		if(minParent < 1){
			stop("at least one observation must be used in each node.")
		}
		if(numTreesInForest < 1){
			stop("at least one tree must be used.")
		}

		if(is.null(numTreeBins)){
			numTreeBins <- numCores
		}

		forest_module <- methods::new(forestPackingRConversion)

		switch(as.character(forestType),
				'rfBase' = {
					forest_module$setParameterString("forestType", "rfBase")
				},
				'rerf'= {
					forest_module$setParameterString("forestType", "rerf")
				},
				'binnedBase' = {
					forest_module$setParameterString("forestType", "binnedBase")
				},
				'binnedBaseRerF' = {
					forest_module$setParameterString("forestType", "binnedBaseRerF")
				},
				'binnedBaseTern' = {
					forest_module$setParameterString("forestType", "binnedBaseTern")
					forest_module$setParameterInt("methodToUse", 1)
				},
				'S-RerF' = {
					forest_module$setParameterString("forestType", "binnedBaseTern")
					forest_module$setParameterInt("methodToUse", 2)
					forest_module$setParameterInt("imageHeight", imageHeight)
					forest_module$setParameterInt("imageWidth", imageWidth)
					forest_module$setParameterInt("patchHeightMax", patchHeightMax)
					forest_module$setParameterInt("patchHeightMin", patchHeightMin)
					forest_module$setParameterInt("patchWidthMax", patchWidthMax)
					forest_module$setParameterInt("patchWidthMin", patchWidthMin)
				},
				{
					warning(sprintf("Using non-standard forestType %s.", forestType))
					forest_module$setParameterString("forestType", forestType)
				}
		)

		forest_module$setParameterInt("numTreesInForest", numTreesInForest)
		if(is.finite(maxDepth) && (maxDepth > 0)){
			forest_module$setParameterInt("maxDepth", maxDepth)
		}
		forest_module$setParameterInt("minParent", minParent)
		forest_module$setParameterInt("numCores", numCores)
		forest_module$setParameterInt("useRowMajor",0)
		forest_module$setParameterInt("seed",seed)

		if(!is.null(nodeSizeToBin) & !is.null(nodeSizeBin)){
			if(nodeSizeBin > nodeSizeToBin){
				stop("nodeSizeBin must be less than or greater than nodeSizeToBin.")
			}
			forest_module$setParameterInt("binSize",nodeSizeBin)
			forest_module$setParameterInt("binMin",nodeSizeToBin)
		}

		### Set MTRY if not NULL
		if(!is.null(mtry)){
		forest_module$setParameterInt("mtry",mtry)
		}
		if(!is.null(mtryMult)){
		forest_module$setParameterDouble("mtryMult",mtryMult)
		}


		##### Check X and Y inputs
		################################################
		if(xor(is.null(X), is.null(Y))){
			stop("X and Y must be set or both must be NULL.")
		}

		if(!is.null(X)){
			X <- as.matrix(X)
			if(class(X[1,1])=="integer"){
				storage.mode(X) <- "numeric"
			}

			Y <- as.integer(Y)	

			if(nrow(X) != length(Y)){
				stop("number of observations in X is different from Y length.")
			}
			forest_module$growForestGivenX(X,Y)


			##### Check CSV info
			################################################
		}else if(!is.null(csvFileName)){
			if(!file.exists(csvFileName)){
				stop("file does not exist.")
			}
			if(is.null(columnWithY)){
				stop("columnWithY cannot be NULL when using CSV.")
			}
			forest_module$setParameterString("CSVFileName", csvFileName)
			forest_module$setParameterInt("columnWithY", columnWithY);
			forest_module$growForestCSV()
		}else{
			stop("no input provided.")
		}
		#forest_module$printParameters()
		return(forest_module)

	}

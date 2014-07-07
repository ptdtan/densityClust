#' Clustering by fast search and find of density peaks
#' 
#' This package implement the clustering algorithm described by Alex Rodriguez
#' and Alessandro Laio (2014). It provides the user with tools for generating 
#' the initial rho and delta values for each observation as well as using these
#' to assign observations to clusters. This is done in two passes so the user is
#' free to reassign observations to clusters using a new set of rho and delta 
#' thresholds, without needing to recalculate everything.
#' 
#' Plotting
#' 
#' Two types of plots are supported by this package, and both mimix the types of
#' plots used in the publication for the algorithm. The standard plot function
#' produces a decision plot, with optional colouring of cluster peaks if these 
#' are assigned. Furthermore \code{\link{plotMDS}} performs a multidimensional 
#' scaling of the distance matrix and plots this as a scatterplot. If clusters
#' are assigned observations are coloured according to their assignment.
#' 
#' Cluster detection
#' 
#' The two main functions for this package are \code{\link{densityClust}} and 
#' \code{\link{findClusters}}. The former takes a distance matrix and optionally
#' a distance cutoff and calculates rho and delta for each observation. The 
#' latter takes the output of \code{\link{densityClust}} and make cluster 
#' assignment for each observation based on a user defined rho and delta 
#' threshold. If the thresholds are not specified the user is able to supply 
#' them interactively by clicking on a decision plot.
#' 
#' @example
#' 
#' @seealso \code{\link{densityClust}}, \code{\link{findClusters}}, \code{\link{plotMDS}}
#' 
#' @references Rodriguez, A., & Laio, A. (2014). Clustering by fast search and find of density peaks. Science, 344(6191), 1492-1496. doi:10.1126/science.1242072
#' 
#' @docType package
#' @name densityClust-package
#' 
NULL

#' Computes the local density of points in a distance matrix
#' 
#' This function takes a distance matrix and a distance cutoff and calculate the
#' local density for each point in the matrix. The computation can either be 
#' done using a simple summation of the points with the distance cutoff for each
#' observation, or by applying a gaussian kernel scaled by the distance cutoff 
#' (more robust for low-density data)
#' 
#' @param distance A distance matrix
#' 
#' @param dc A numeric value specifying the distance cutoff
#' 
#' @param gaussian Logical. Should a gaussian kernel be used to estimate the 
#' density (defaults to FALSE)
#' 
#' @return A vector of local density values, the index matching row and column 
#' indexes in the distance matrix
#' 
#' @noRd
#' 
localDensity <- function(distance, dc, gaussian=FALSE) {
    comb <- as.matrix(distance)
    if(gaussian) {
        res <- apply(exp(-(comb/dc)^2), 1, sum)-1
    } else {
        res <- apply(comb < dc, 1, sum)-1
    }
    if(is.null(attr(distance, 'Labels'))) {
        names(res) <- NULL
    } else {
        names(res) <- attr(distance, 'Labels')
    }
    res
}
#' Calculate distance to closest observation of higher density
#' 
#' This function finds, for each observation, the minimum distance to an 
#' observation of higher local density.
#' 
#' @param distance A distance matrix
#' 
#' @param rho A vector of local density values as outputted by localDensity()
#' 
#' @return A vector of distances with index matching the index in rho
#' 
#' @noRd
#' 
distanceToPeak <- function(distance, rho) {
    comb <- as.matrix(distance)
    res <- sapply(1:length(rho), function(i) {
        peaks <- comb[rho>rho[i], i]
        if(length(peaks) == 0) {
            max(comb[,i])
        } else {
            min(peaks)
        }
    })
    names(res) <- names(rho)
    res
}
#' Estimate the distance cutoff for a specified neighbor rate
#' 
#' This function calculates a distance cutoff value for a specific distance 
#' matrix that makes the average neighbor rate (number of points within the
#' distance cutoff value) fall between the provided range. The authors of the
#' algorithm suggests aiming for a neighbor rate between 1 and 2 percent, but 
#' also states that the algorithm is quite robust with regards to more extreme
#' cases.
#' 
#' @param distance A distance matrix
#' 
#' @param neighborRateLow The lower bound of the neighbor rate
#' 
#' @param neighborRateHigh The upper bound of the neighbor rate
#' 
#' @return A numeric value giving the estimated distance cutoff value
#' 
#' @references Rodriguez, A., & Laio, A. (2014). Clustering by fast search and find of density peaks. Science, 344(6191), 1492-1496. doi:10.1126/science.1242072
#' 
#' @export
#' 
estimateDc <- function(distance, neighborRateLow=0.01, neighborRateHigh=0.02) {
    comb <- as.matrix(distance)
    size <- attr(distance, 'Size')
    dc <- min(distance)
    dcMod <- as.numeric(summary(distance)['Median']*0.01)
    while(TRUE) {
        neighborRate <- mean((apply(comb < dc, 1, sum)-1)/size)
        if(neighborRate > neighborRateLow && neighborRate < neighborRateHigh) break
        if(neighborRate > neighborRateHigh) {
            dc <- dc - dcMod
            dcMod <- dcMod/2
        }
        dc <- dc + dcMod
    }
    cat('Distance cutoff calculated to', dc, '\n')
    dc
}
#' Calculate clustering attributes based on the densityClust algorithm
#' 
#' This function takes a distance matrix and optionally a distance cutoff and 
#' calculates the values necessary for clustering based on the algorithm 
#' proposed by Alex Rodrigues and Alessandro Laio (see references). The actual 
#' assignment to clusters are done in a later step, based on user defined 
#' threshold values.
#' 
#' @details
#' The function calculates rho and delta for the observations in the provided 
#' distance matrix. If a distance cutoff is not provided this is first estimated
#' using \code{\link{estimateDc}} with default values.
#' 
#' The information kept in the densityCluster object is:
#' \describe{
#'   \item{rho}{A vector of local density values}
#'   \item{delta}{A vector of minimum distances to observations of higher density}
#'   \item{distance}{The initial distance matrix}
#'   \item{labels}{The observation labels, if any, from the original data}
#'   \item{dc}{The distance cutoff used to calculate rho}
#'   \item{threshold}{A named vector specifying the threshold values for rho and delta used for cluster detection}
#'   \item{peaks}{A vector of indexes specifying the cluster center for each cluster}
#'   \item{clusters}{A vector of cluster affiliations for each observation. The clusters are referenced as indexes in the peaks vector}
#'   \item{halo}{A logical vector specifying for each observation if it is considered part of the halo}
#' }
#' Before running findClusters the threshold, peaks, clusters and halo data is 
#' NA.
#' 
#' @param distance A distance matrix
#' 
#' @param dc A distance cutoff for calculating the local density. If missing it
#' will be estimated with estimateDc(distance)
#' 
#' @param gaussian Logical. Should a gaussian kernel be used to estimate the 
#' density (defaults to FALSE)
#' 
#' @return A densityCluster object. See details for a description.
#' 
#' @seealso \code{\link{estimateDc}}, \code{\link{findClusters}}
#' 
#' @references Rodriguez, A., & Laio, A. (2014). Clustering by fast search and find of density peaks. Science, 344(6191), 1492-1496. doi:10.1126/science.1242072
#' 
#' @export
#' 
densityClust <- function(distance, dc, gaussian=FALSE) {
    if(missing(dc)) {
        dc <- estimateDc(distance)
    }
    rho <- localDensity(distance, dc, gaussian=gaussian)
    delta <- distanceToPeak(distance, rho)
    res <- list(rho=rho, delta=delta, distance=distance, labels=attr(distance, 'Labels'), dc=dc, threshold=c(rho=NA, delta=NA), peaks=NA, clusters=NA, halo=NA)
    class(res) <- 'densityCluster'
    res
}
#' @export
#' 
#' @noRd
#' 
plot.densityCluster <- function(x, ...) {
    plot(x$rho, x$delta, main='Decision graph', xlab=expression(rho), ylab=expression(delta))
    if(!is.na(x$peaks[1])) {
        points(x$rho[x$peaks], x$delta[x$peaks], col=2:(1+length(x$peaks)), pch=19)
    }
}
#' Plot observations using multidimensional scaling and colour by cluster
#' 
#' This function produces an MDS scatterplot based on the distance matrix of the
#' densityCluster object, and, if clusters are defined, colours each observation
#' according to cluster affiliation. Observations belonging to a cluster core is
#' plotted with filled circles and observations belonging to the halo with
#' hollow circles.
#' 
#' @param x A densityCluster object as produced by \code{\link{densityClust}}
#' 
#' @param ... Additional parameters. Currently ignored
#' 
#' @seealso \code{\link{densityClust}}
#' 
#' @export
#' 
plotMDS <- function (x, ...) {
    UseMethod("plotMDS", x)
}
plotMDS.densityCluster <- function(x) {
    mds <- cmdscale(x$distance)
    plot(mds[,1], mds[,2], xlab='', ylab='', main='MDS plot of observations')
    if(!is.na(x$peaks[1])) {
        for(i in 1:length(x$peaks)) {
            ind <- which(x$clusters == i)
            points(mds[ind, 1], mds[ind, 2], col=i+1, pch=ifelse(x$halo[ind], 1, 19))
        }
        legend('topright', legend=c('core', 'halo'), pch=c(19, 1), horiz=TRUE)
    }
}
#' @export
#' 
#' @noRd
#' 
print.densityCluster <- function(x, ...) {
    if(is.na(x$peaks[1])) {
        cat('A densityCluster object with no clusters defined\n\n')
        cat('Number of observations:', length(x$rho), '\n')
    } else {
        cat('A densityCluster object with', length(x$peaks), 'clusters defined\n\n')
        cat('Number of observations:', length(x$rho), '\n')
        cat('Observations in core:  ', sum(!x$halo), '\n\n')
        cat('Parameters:\n')
        cat('dc (distance cutoff)   rho threshold          delta threshold\n')
        cat(formatC(x$dc, width=-22), formatC(x$threshold[1], width=-22), x$threshold[2])
    }
}
#' Detect clusters in a densityCluster obejct
#' 
#' This function uses the supplied rho and delta thresholds to detect cluster
#' peaks and assign the rest of the observations to one of these clusters. 
#' Furthermore core/halo status is calculated. If either rho or delta threshold
#' is missing the user is presented with a decision plot where they are able to
#' click on the plot area to set the treshold. If either rho or delta is set, 
#' this takes presedence over the value found by clicking.
#' 
#' @param x A densityCluster object as produced by \code{\link{densityClust}}
#' 
#' @param ... Additional parameters passed on to \code{\link{findClusters.densityCluster}}
#' 
#' @return A densityCluster object with clusters assigned to all observations
#' 
#' @seealso \code{\link{findClusters}}
#' 
#' @references Rodriguez, A., & Laio, A. (2014). Clustering by fast search and find of density peaks. Science, 344(6191), 1492-1496. doi:10.1126/science.1242072
#' 
#' @export
#' 
findClusters <- function (x, ...) {
    UseMethod("findClusters", x)
}
#' @rdname findClusters
#' 
#' @param rho The threshold for local density when detecting cluster peaks
#' 
#' @param delta The threshold for minimum distance to higher density when detecting cluster peaks
#' 
#' @param plot Logical. Should a decision plot be shown after cluster detection
#' 
findClusters.densityCluster <- function(x, rho, delta, plot=FALSE) {
    if(missing(rho) || missing(delta)) {
        x$peaks <- NA
        plot(x)
        cat('Click on plot to select thresholds\n')
        threshold <- locator(1)
        if(missing(rho)) rho <- threshold$x
        if(missing(delta)) delta <- threshold$y
        plot=TRUE
    }
    x$peaks <- which(x$rho > rho & x$delta > delta)
    x$threshold['rho'] <- rho
    x$threshold['delta'] <- delta
    
    if(plot) {
        plot(x)
    }
    
    comb <- as.matrix(x$distance)
    runOrder <- order(x$rho, decreasing = TRUE)
    cluster <- rep(NA, length(x$rho))
    for(i in runOrder) {
        if(i %in% x$peaks) {
            cluster[i] <- match(i, x$peaks)
        } else {
            higherDensity <- which(x$rho>x$rho[i])
            cluster[i] <- cluster[higherDensity[which.min(comb[i, higherDensity])]]
        }
    }
    x$clusters <- cluster
    border <- rep(0, length(x$peaks))
    for(i in 1:length(x$peaks)) {
        averageRho <- outer(x$rho[cluster == i], x$rho[cluster != i], function(X, Y){X})
        index <- comb[cluster == i, cluster != i] <= x$dc
        if(any(index)) border[i] <- max(averageRho[index])
    }
    halo <- rep(FALSE, length(cluster))
    for(i in 1:length(cluster)) {
        halo[i] <- x$rho[i] < border[cluster[i]]
    }
    x$halo <- halo
    x
}
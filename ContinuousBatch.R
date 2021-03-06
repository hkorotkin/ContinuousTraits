library(geiger)
setwd("/Users/Hailee/Documents/School/Grad_School/Spring_2016/PhyloMeth/Correlation")

source("CorrelationFunctions.R") # this isn't working?
tree <- get_study_tree("pg_2346","tree4944")
plot(tree,cex=0.3)
discrete.data <- as.matrix(read.csv(file="/Users/Hailee/Desktop/taxa.csv", stringsAsFactors=FALSE,row.names=NULL))#death to factors.
discrete.data2 <- as.matrix(read.csv(file="/Users/Hailee/Desktop/taxa.csv", stringsAsFactors=FALSE,row.names=1))#death to factors.

latitude<- rnorm(128,mean=89,sd=0.5)
height<-rnorm(128,mean=2,sd=0.5)
continuous.data<-cbind(latitude,height)
rownames(continuous.data)<-tree$tip.label


cleaned.continuous <- CleanData(tree, continuous.data)
cleaned.discrete <- CleanData(tree, discrete.data2)
VisualizeData(tree, cleaned.continuous)
VisualizeData(tree, cleaned.discrete)

#First, start basic. What is the rate of evolution of your trait on the tree? 

BM1 <- fitContinuous(tree, cleaned.continuous$data, model="BM")
print(paste("The rate of evolution is", BM1$latitude[[4]]$sigsq, "in units of"))
#Important: What are the rates of evolution? In what units?
OU1 <- fitContinuous(tree, cleaned.continuous$data[,'latitude'], model="OU")
par(mfcol=c(1,2))
plot(tree, show.tip.label=FALSE)
ou.tree <- rescale(tree, model="OU", alpha=OU1[[4]]$alpha)
plot(ou.tree,show.tip.label=FALSE)
#How are the trees different?

#Compare trees
AIC.BM1 <- BM1$latitude[[4]]$aic
AIC.OU1 <- OU1[[4]]$aic
delta.AIC.BM1 <-AIC.BM1 - min(c(AIC.BM1,AIC.OU1))
delta.AIC.OU1 <- AIC.OU1 - min(c(AIC.BM1,AIC.OU1))



#OUwie runs:
#This takes longer than you may be used to. 
#We're a bit obsessive about doing multiple starts and in general
#performing a thorough numerical search. It took you 3+ years
#to get the data, may as well take an extra five minutes to 
#get an accurate answer

#First, we need to assign regimes. The way we do this is with ancestral state estimation of a discrete trait.
#We can do this using ace() in ape, or similar functions in corHMM or diversitree. Use only one discrete char
one.discrete.char <- discrete.data[,"saprotrophic"]
names(one.discrete.char)<-tree$tip.label
reconstruction.info <- ace(one.discrete.char, tree, type="discrete", method="ML", CI=TRUE)#maybe change to true
best.states <- apply(reconstruction.info$lik.anc, 1, which.max)


#NOW ADD THESE AS NODE LABELS TO YOUR TREE

labeled.tree <-tree; labeled.tree$node.label <- best.states

tips<-rownames(cleaned.continuous$data)
cleaned.continuous2<-data.frame(tips,cleaned.discrete$data[,'saprotrophic'],cleaned.continuous$data[,'latitude'])
colnames(cleaned.continuous2) <- c("tips","regime","latitude")

nodeBased.OUMV <- OUwie(labeled.tree, cleaned.continuous2,model="OUMV", simmap.tree=FALSE, diagn=FALSE)
print(nodeBased.OUMV)
#What do the numbers mean?
#Warning with this?

#Now run all OUwie models:
models <- c("BM1","BMS","OU1","OUMV","OUMA","OUMVA") ##OUM not working
results <- lapply(models, RunSingleOUwieModel, phy=labeled.tree, data=cleaned.continuous2)



AICc.values<-sapply(results, "[[", "AICc")
names(AICc.values)<-models
AICc.values<-AICc.values-min(AICc.values)


print(AICc.values) #The best model is the one with smallest AICc score

best<-results[[which.min(AICc.values)]] #store for later

print(best) #prints info on best model


#We get SE for the optima (see nodeBased.OUMV$theta) but not for the other parameters. Let's see how hard they are to estimate. 
#First, look at ?OUwie.fixed to see how to calculate likelihood at a single point.
?OUwie.fixed

#Next, keep all parameters but alpha at their maximum likelihood estimates (better would be to fix just alpha and let the others optimize given this constraint, but this is harder to program for this class). Try a range of alpha values and plot the likelihood against this.
alpha.values<-seq(from=0.1, to=1, length.out=50)

#keep it simple (and slow) and do a for loop:
likelihood.values <- rep(NA, length(alpha.values))
for (iteration in sequence(length(alpha.values))) {
	likelihood.values[iteration] <- OUwie.fixed(labeled.tree, data=cleaned.continuous2, model="OUMVA", alpha=rep(alpha.values[iteration]), sigma.sq=best$solution[2,], theta=best$theta[,1])$loglik
}

plot(x=alpha.values, y=likelihood.values, xlab="Aplha", ylab="Log Likelihood", type="l", bty="n")


points(x=best$solution[1,1], y=best$loglik, pch=16, col="red")
text(x=best$solution[1,1], y=best$loglik, "unconstrained best", pos=4, col="red")

#a rule of thumb for confidence for likelihood is all points two log likelihood units worse than the best value. Draw a dotted line on the plot to show this
abline(h=best$loglik-2, lty="dotted") #Two log-likelihood 


#Now, let's try looking at both theta parameters at once, keeping the other parameters at their MLEs
require("akima")

nreps<-400
theta1.points<-c(best$theta[1,1], rnorm(nreps-1, best$theta[1,1], 5*best$theta[1,2])) #center on optimal value, have extra variance
theta2.points<-c(best$theta[2,1], rnorm(nreps-1, best$theta[2,1], 5*best$theta[2,2])) #center on optimal value, have extra variance
likelihood.values<-rep(NA,nreps)

for (iteration in sequence(nreps)) {
	likelihood.values[iteration] <- OUwie.fixed(labeled.tree, cleaned.continuous2, model="OUMVA", alpha=best$solution[1,], sigma.sq=best$solution[2,], theta=c(theta1.points[iteration], theta2.points[iteration]))$loglik
}
#think of how long that took to do 400 iterations. Now remember how long the search took (longer).

likelihood.differences<-(-(likelihood.values-max(likelihood.values)))

#We are interpolating here: contour wants a nice grid. But by centering our simulations on the MLE values, we made sure to sample most thoroughly there
interpolated.points<-interp(x=theta1.points, y=theta2.points, z= likelihood.differences, linear=FALSE, extrap=TRUE, xo=seq(min(theta1.points), max(theta1.points), length = 400), yo=seq(min(theta2.points), max(theta2.points), length = 400))
	
contour(interpolated.points, xlim=range(c(theta1.points, theta2.points)),ylim=range(c(theta1.points, theta2.points)), xlab="Theta 1", ylab="Theta 2", levels=c(2,5,10),add=FALSE,lwd=1, bty="n", asp=1)

points(x=best$theta[1,1], y=best$theta[2,1], col="red", pch=16)

points(x=cleaned.continuous2$X[which(cleaned.continuous2$Reg==1)],y=rep(min(c(theta1.points, theta2.points)), length(which(cleaned.continuous2$Reg==1))), pch=18, col=rgb(0,0,0,.3)) #the tip values in regime 1, plotted along x axis
points(y=cleaned.continuous2$X[which(cleaned.continuous2$Reg==2)],x=rep(min(c(theta1.points, theta2.points)), length(which(cleaned.continuous2$Reg==2))), pch=18, col=rgb(0,0,0,.3)) #the tip values in regime 2, plotted along y axis


#The below only works if the discrete trait rate is low, so you have a good chance of estimating where the state is.
#If it evolves quickly, hard to estimate where the regimes are, so some in regime 1 are incorrectly mapped in
#regime 2 vice versa. This makes the models more similar than they should be.
#See Revell 2013, DOI:10.1093/sysbio/sys084 for an exploration of this effect.
library(phytools)
trait.ordered<-data.frame(cleaned.continuous2[,2], cleaned.continuous2[,2],row.names=cleaned.continuous2[,1])
trait.ordered<- trait.ordered[tree$tip.label,]
z<-trait.ordered[,1]
names(z)<-rownames(trait.ordered)
tree.mapped<-make.simmap(labeled.tree,z,model="ER",nsim=1)
leg<-c("black","red")
names(leg)<-c(1,2)
plotSimmap(tree.mapped,leg,pts=FALSE,ftype="off", lwd=1)

simmapBased<-OUwie(tree.mapped,cleaned.continuous2,model="OUMVA", simmap.tree=TRUE, diagn=FALSE)
print(simmapBased)
#How does this compare to our best model from above? Should they be directly comparable?
print(best)

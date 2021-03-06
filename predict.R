# Make predictions of Systole and Diastole for all datasets.

# Uses "segments-classified.csv" to create a model to help find LV segments, then filters and
# aggregates the segment data to have one set of meta-info per ID. Combines this with the 
# train set to create a model for the Systole and Diastole volumes.

# Volume = sum area * slice thickness over slices for a certain Time
# Min and Max volumes are the systole/diastole values

# 0 - LB 0.036205 / local score .023 or something like that (strongly overfitting?)
# * - see what improvement is with just better segmentation data ()
#     LB 0.033975 / local score 0.02804779 / avg val error Sys 33.16965, Dia 39.21235
#   ==> better segmentation data helps
# * - what if not doing outlier detection, just smoothing
#     LB 0.038827
#   ==> keep outlier detection
#     now back to local score 0.02822668 / Avg error 29.5967 37.08891 / Corr 0.7989748 0.841306
# *   LB 0.035878 after "fixing" a bug that did not set area to 0 for low pLV (threshold 0.2)
#       local score was 0.02582455 / Avg error 28.09956 37.11775 / Corr 0.8361123 0.8583229
#   ==> set pLV threshold even lower (0.1 instead of 0.2) or should it be NA ??
# * - what if smoothing also for other predictors than area
#     LB 0.035684 / Local 0.02642635 / Avg error 30.67679 37.77851 / Corr 0.8372744 0.8607076
#   ==> using other than area minimal effect
# * - even more segmentation results
#     LB 0.033614 / Local 0.02567658 / Avg error 32.26049 32.26049 / Corr 0.8202784 0.8632017
# * - what if just imputation, not smoothing
# * - what if using simple lm / glm instead of gbm

# Total new segmentation
# LB 0.032663
# Average error on Systole on validation set: 25.48068
# Average error on Diastole on validation set: 31.72199
# Creating submission scores for range 1001 1400
# Correlations on 500 cases:
#   [1] 0.8634994
# [1] 0.8906129
# CRPS score on train set: 0.02275966

# pLV 0.1 ipv 0.0
# LB 0.032257
# Average error on Systole on validation set: 23.91543
# Average error on Diastole on validation set: 32.43053
# Creating submission scores for range 1001 1400
# Correlations on 500 cases:
#   [1] 0.8757999
# [1] 0.8925369
# CRPS score on train set: 0.02262955

# setting to NA instead of 0 if below threshold
# 0.033411 --> not an improvement
# Average error on Systole on validation set: 23.99993
# Average error on Diastole on validation set: 32.07489
# Creating submission scores for range 1001 1400
# Correlations on 500 cases:
#   [1] 0.8607654
# [1] 0.884918
# CRPS score on train set: 0.02311668

# More classification ==> didnt help?!
# LB  0.032636
# Average error on Systole on validation set: 23.353
# Average error on Diastole on validation set: 32.38319
# Creating submission scores for range 1001 1400
# Correlations on 500 cases:
#   [1] 0.8783367
# [1] 0.8928728
# CRPS score on train set: 0.02221571

# pLV threshold at 1.5 ==> small improvement maybe
# 0.032379
# Average error on Systole on validation set: 26.08395
# Average error on Diastole on validation set: 33.38799
# Creating submission scores for range 1001 1400
# Correlations on 500 cases:
#   [1] 0.8820561
# [1] 0.8941455
# CRPS score on train set: 0.02196425

# imputeFieldNames all fields, pLV threshold 1.5, back to previous classification set
# LB 0.031747
# Average error on Systole on validation set: 24.99006
# Average error on Diastole on validation set: 33.35922
# Creating submission scores for range 1001 1400
# Correlations on 500 cases:
#   [1] 0.8733627
# [1] 0.8891473
# CRPS score on train set: 0.02295507

# Different GBM tuning, 20 rounds
# LB = 0.032339 (overfitting?)
# Average error on Systole on validation set: 24.38146
# Average error on Diastole on validation set: 31.37729
# [1] 0.8949208
# [1] 0.9064123
# CRPS score on train set: 0.02274522

# 100 rounds…
# LB = 0.032074 (best 0.031747)
# Average error on Systole on validation set: 24.58165
# Average error on Diastole on validation set: 32.68044
# [1] 0.8964039
# [1] 0.905866
# CRPS score on train set: 0.02245511

# Old GBM settings, 100 rounds
# LB = 0.031626
# Average error on Systole on validation set: 25.00166
# Average error on Diastole on validation set: 32.84126
# Correlations on 500 cases:
#   [1] 0.8728571
# [1] 0.8907102
# CRPS score on train set: 0.02272002

# LB 0.030880
# with pLV threshold to 2.5 instead of 2
# Average error on Systole on validation set: 24.76124
# Average error on Diastole on validation set: 32.9024
# Creating submission scores for range 1001 1400
# Correlations on 500 cases:
#   [1] 0.8805198
# [1] 0.8925185
# CRPS score on train set: 0.0223398

# FINAL STAGE 1 LB 0.030879
# with 500 rounds in final model instead of 100
# Average error on Systole on validation set: 24.91311
# Average error on Diastole on validation set: 33.08062
# [1] 0.8810654
# [1] 0.8925299
# CRPS score on train set: 0.0223377

# TODO
# p10/p90 instead of min/max
# pLV threshold larger
# min observations

source("util.R")

library(caret)
library(pROC)
library(lattice)
require(caret)
library(DMwR) # outlier detection
require(mgcv) # 3D smoothing

# Threshold for LV segment probability
pSegmentThreshold <- 0.25
defaultArea <- 0 # replacement value when pLV below threshold

# Used both in segment and case prediction
validationPercentage <- 0.20

# Max Volume (mL) - fixed value used in submissions
MAXVOLUME <- 600

# Identify the LV segments in the whole dataset by creating a model
# from the (manually) identified ones
classifiedSegments <- fread('segments-predict.csv') 

print("Reading image meta data")
imageList <- getImageList()

print("Reading train data")
trainVolumes <- fread('data/train.csv') 

# Random IDs from train set for plotting
sampleIds <- sample(unique(trainVolumes$Id), 10)

print("Reading segmentation")

imagePredictFile <- "allSegments-segmentsPredicted.csv"
segmentPredictFile <- "segmentTrainSet.csv"

skipSegmentPrediction <- F

if (skipSegmentPrediction & file.exists(imagePredictFile)) {
  # Keep data if we want to skip the segmentation predict phase
  print("!! Skipping segment prediction")
  allSegments <- fread(imagePredictFile)
} else {
  
  allSegments <- NULL
  for (dataset in unique(imageList$Dataset)) {
    if (file.exists(getSegmentFile(dataset))) {
      segmentsPerDataset <- fread(getSegmentFile(dataset))
      if (is.null(allSegments)) {
        allSegments <- segmentsPerDataset
      } else {
        removedSet <- setdiff(names(allSegments), names(segmentsPerDataset))
        addedSet <- setdiff(names(segmentsPerDataset), names(allSegments))
        diffSet <- paste(c(paste("-",removedSet), paste("+",addedSet)),collapse=", ")
        if (length(removedSet) + length(addedSet) > 0) {
          print(names(allSegments))
          print(names(segmentsPerDataset))
          print(diffSet)
          stop("Datasets do not match up. Please consider removing files.")
        }
        allSegments <- rbind(allSegments, segmentsPerDataset)
      }
    }
  }
  setkey(allSegments, Id, Slice, Time, UUID)
  
  # First, match the ones with the same UUID
  segClassificationSet <- left_join(select(classifiedSegments, Id, Slice, Time, UUID, isLV), 
                                    allSegments, 
                                    by=c("Id", "Slice", "Time", "UUID"))
  
  # For the others, find the best segment match per each Id/Slice/Time
  # TODO: not sure what happens if none of the UUID's match
  newSegmentationOldClassification <- filter(segClassificationSet, is.na(m.cx))
  segClassificationSet <- filter(segClassificationSet, !is.na(m.cx))
  
  if (nrow(newSegmentationOldClassification) > 0) {
    classifiedSegmentsOlder <- left_join(select(newSegmentationOldClassification, Id, Slice, Time, UUID, isLV),
                                         select(classifiedSegments, Id, Slice, Time, UUID, isLV, m.cx, m.cy))
    classifiedImagesOlder <- unique(select(classifiedSegmentsOlder, Id, Slice, Time))
    cat(nrow(classifiedImagesOlder), "images have new segmentation to match with existing classification",fill=T)
    allCandidateSegments <- left_join(classifiedImagesOlder, allSegments, by=c("Id","Slice","Time"))
    
    prevId <- -1
    prevSlice <- -1
    for (i in seq(nrow(classifiedImagesOlder))) {
      candidateSegments <- filter(allCandidateSegments, 
                                  Id==classifiedImagesOlder$Id[i], 
                                  Slice==classifiedImagesOlder$Slice[i], 
                                  Time==classifiedImagesOlder$Time[i]) # all segs in this image
      lv <- left_join(classifiedImagesOlder[i], 
                      classifiedSegmentsOlder, 
                      by=c("Id","Slice","Time")) %>% filter(isLV) # classified LV in this image
      if (!(prevId == classifiedImagesOlder$Id[i] & prevSlice == classifiedImagesOlder$Slice[i])) {
        cat("Matching existing classification to new segmentation for Id", classifiedImagesOlder$Id[i], 
            "Slice", classifiedImagesOlder$Slice[i], 
            "#img", nrow(filter(classifiedImagesOlder, Id == classifiedImagesOlder$Id[i], Slice == classifiedImagesOlder$Slice[i])), 
            "#segs:", nrow(candidateSegments), 
            "==>", nrow(lv), fill=T)
        prevId <- classifiedImagesOlder$Id[i]
        prevSlice <- classifiedImagesOlder$Slice[i]
      }
      
      candidateSegments$isLV <- NA
      candidateSegments <- candidateSegments[,names(newSegmentationOldClassification),with=F] # make sure cols have the same order
      
      if (nrow(lv) == 1) {
        # Set LV to the segment closest to the identified one. Note: similar code in classify.R
        distToLVSeg <- sqrt((candidateSegments$m.cx - lv$m.cx)^2 + (candidateSegments$m.cy - lv$m.cy)^2)
        segLV <- candidateSegments$segIndex[which.min(distToLVSeg)]
        candidateSegments$isLV <- (candidateSegments$segIndex == segLV & distToLVSeg < 5) # abs distance threshold like in classify.R
        segClassificationSet <- rbind(segClassificationSet, candidateSegments)
      } else {
        cat("WARN:",nrow(lv),"LV segments in image", classifiedImagesOlder$Time[i], fill=T)
      }
      
      segClassificationSet <- rbind(segClassificationSet, candidateSegments)
    }
  }
  
  # Quick report on the segmentation prediction data set.
  cat("Segment predict set has",nrow(segClassificationSet),"observations with a pos rate of",sum(segClassificationSet$isLV,na.rm=T)/nrow(segClassificationSet),fill=T)
  cat("   number of Ids   :",nrow(unique(select(segClassificationSet,Id))),"with identified LV",nrow(unique(select(filter(segClassificationSet,isLV),Id))),fill=T)
  cat("   number of Slices:",nrow(unique(select(segClassificationSet,Id,Slice))),"with identified LV",nrow(unique(select(filter(segClassificationSet,isLV),Id,Slice))),fill=T)
  cat("   number of Images:",nrow(unique(select(segClassificationSet,Id,Slice,Time))),"with identified LV",nrow(unique(select(filter(segClassificationSet,isLV),Id,Slice,Time))),fill=T)
  
  # Build up prediction set by creating derived variables and dropping non-predictors
  segClassificationSetIDs <- select(segClassificationSet, Id, Slice, Time)
  segClassificationSetWithMetaData <- left_join(segClassificationSet, 
                                                imageList, by=c("Id","Slice","Time"))
  setkeyv(segClassificationSetWithMetaData, c("Id","Slice","Time","segIndex")) # TODO why are there duplicates? roughly 2x.
  segClassificationSet <- createSegmentPredictSet(filter(unique(segClassificationSetWithMetaData), !is.na(isLV)))
  
  # Build up the data set for training and classification
  valSet <- sample.int(nrow(segClassificationSet), validationPercentage*nrow(segClassificationSet))
  trainDataPredictorsOnly <- select(segClassificationSet, -isLV)
  
  cat("Building segment model with",length(names(trainDataPredictorsOnly)),"predictors",fill=T)
  uniVariateAnalysis <- data.frame(Predictor=names(trainDataPredictorsOnly),
                                   validation=sapply(trainDataPredictorsOnly, 
                                                     function(p) {auc(segClassificationSet$isLV[valSet], p[valSet])}),
                                   train=sapply(trainDataPredictorsOnly, 
                                                function(p) {auc(segClassificationSet$isLV[-valSet], p[-valSet])}))
  uniVariateAnalysis <- gather(uniVariateAnalysis, dataset, auc, -Predictor)
  uniVariateAnalysis$Predictor <- factor(uniVariateAnalysis$Predictor, levels=arrange(uniVariateAnalysis,-auc)$Predictor)
  print(ggplot(uniVariateAnalysis, aes(x=Predictor, y=auc, fill=dataset))+
          geom_bar(stat="identity",position="dodge")+
          theme(axis.text.x = element_text(angle = 45, hjust=1))+
          geom_hline(yintercept=0.52,linetype="dashed")+
          ggtitle("AUC of individual predictors for segmentation model"))
  
  leftVentricleSegmentModel <- xgboost(data = data.matrix(trainDataPredictorsOnly[-valSet]), 
                                       label = segClassificationSet$isLV[-valSet], 
                                       max.depth = 6, eta = 0.1, nround = 70,
                                       objective = "binary:logistic", 
                                       missing=NaN, verbose=0)
  imp_matrix <- xgb.importance(feature_names = names(trainDataPredictorsOnly), model = leftVentricleSegmentModel)
  print(xgb.plot.importance(importance_matrix = imp_matrix))
  
  # Get an idea of the accuracy. Note, it seems very high always.
  probLV <- predict(leftVentricleSegmentModel, data.matrix(trainDataPredictorsOnly), missing=NaN)
  cat("AUC for validation set:", auc(segClassificationSet$isLV[valSet], probLV[valSet]), fill=T)
  
  # Distribution of probabilities
  plotSet <- group_by(data.frame(predictedProbability = cut(probLV, 10), #cut2(probLV, g=20), # equi-weight
                                 isLV = segClassificationSet$isLV,
                                 isVal = (seq(nrow(segClassificationSet)) %in% valSet)), predictedProbability) %>% 
    dplyr::summarise(validation = sum(isLV & isVal)/sum(isVal),
              train = sum(isLV & !isVal)/sum(!isVal),
              count = n()) %>%
    gather(dataset, probability, -count, -predictedProbability)
  print(ggplot(plotSet, aes(x=predictedProbability, y=probability, fill=dataset)) + 
          geom_bar(stat="identity",position="dodge") + 
          ggtitle("Segment Prediction") +
          theme(axis.text.x = element_text(angle = 45, hjust = 1)))
  
  # Keep data for analysis elsewhere
  write.csv(segClassificationSet, segmentPredictFile, row.names=F)
  
  # Apply on full dataset
  cat("Apply segment model to", nrow(allSegments), "segments", fill=T)
  allSegments$pLV <- predict(leftVentricleSegmentModel, 
                             data.matrix(createSegmentPredictSet(
                               left_join(allSegments, 
                                         imageList, by=c("Id","Slice","Time")))),
                             missing=NaN)
  
  # Keep data if we want to skip the segmentation predict phase
  allSegments <- select(allSegments, -UUID)
  write.csv(allSegments, imagePredictFile, row.names=F)
}

# segClassificationSet = dataset with truth in isLV

# Remove segments with pLV < threshold
# Keep only the segments with max pLV for each image
allSegments[, isLV := segIndex == segIndex[which.max(pLV)], by=c("Id","Slice","Time")]
ggplot(allSegments, aes(x=pLV,fill=isLV))+stat_bin(breaks=seq(0,1,by=0.05))+ggtitle("Distribution of best pLV per image")

allSegments <- filter(allSegments, isLV)

imageData <- createImagePredictSet(left_join(imageList, 
                                             allSegments,
                                             by=c("Id", "Slice", "Time")))
cat("Total",nrow(imageData),"images, of which",nrow(allSegments),"have a detected LV",fill=T)

# This should show that lower slice order have a higher probabilities for the left ventricle (better segmentation)
pLeftVentricle <- cut(imageData$pLV,breaks=seq(0,1,by=0.1))
print(ggplot(imageData, aes(x=pLeftVentricle, fill=factor(SliceOrder))) + geom_bar(position="dodge")+
        ggtitle("LV Probability vs Slice Order") +
        theme(axis.text.x = element_text(angle = 45, hjust = 1)))

# If probability of pLV is too low, assume the segment is zero size. 
imputeFieldNames <- c("area", "area.ellipse", "radius.max", "radius.mean", "radius.min")
# imputeFieldNames <- c("area")

for (imputeFieldName in imputeFieldNames) {
  imageData[pLV < pSegmentThreshold, c(imputeFieldName) := c(defaultArea)]
}

# Data cleansing: outlier detection and missing value imputation
# if so, make sure to set those to NA or zero as well when pLV is too low
imageData$RatioOutlier <- 0.0
imageData$RatioMissing <- 0.0
for (imputeFieldName in imputeFieldNames) {
  zRange <- range(0: quantile(imageData[[imputeFieldName]], na.rm=T, p=0.90)) 
  
  for (plotId in unique(imageData$Id)) {
    data3D <- imageData[Id == plotId, sapply(imageData, is.numeric), with=F]
    data3D$imputeField <- data3D[[imputeFieldName]]
    
    # View raw data - with missing and outliers
    print(wireframe(imputeField ~ Time*SliceLocation, data=data3D,
                    shade=T, col.regions = terrain.colors(100), 
                    main=paste("Raw Id=",plotId),
                    zlim=zRange))
    
    # Outliers removal by time and slice (TODO cant we do this at once somehow?)
    similarityData <- select(data3D, SliceLocation, Time, imputeField)
    nOutliers <- 0
    
    doOutlierDetection <- T
    
    if (doOutlierDetection) {
      for (t in unique(similarityData$Time)) {
        d <- similarityData[Time==t]$imputeField
        if (sum(!is.na(d)) > 3) {
          outlier.scores <- lofactor(na.omit(d), k=3)
          #plot(density(outlier.scores))
          outliers <- which(!is.na(d))[which(outlier.scores > 3.0)] # somewhat arbitrary
          nOutliers <- nOutliers + length(outliers)
          outlierSlices <- similarityData[Time==t]$SliceLocation[outliers]
          data3D[Time==t & SliceLocation %in% outlierSlices, imputeField := NA]
        }
      }
      
      for (s in unique(similarityData$SliceLocation)) {
        d <- similarityData[SliceLocation==s]$imputeField
        if (sum(!is.na(d)) > 3) {
          outlier.scores <- lofactor(na.omit(d), k=3)
          #plot(density(outlier.scores))
          outliers <- which(!is.na(d))[which(outlier.scores > 3.0)] # somewhat arbitrary
          nOutliers <- nOutliers + length(outliers)
          outlierTimes <- similarityData[SliceLocation==s]$Time[outliers]
          data3D[SliceLocation==s & Time %in% outlierTimes, imputeField := NA]
        }
      }
    }
    
    outlierRatio <- nOutliers/(length(unique(similarityData$Time))*length(unique(similarityData$Slice)))
    missingRatio <- sum(is.na(data3D$imputeField))/length(data3D$imputeField)
    cat("Id", plotId, "$", imputeFieldName,
        "outliers", paste(round(100*outlierRatio,1),"%",sep=""), 
        "missing", paste(round(100*missingRatio,1),"%",sep=""), fill=T)
    
    #   outlier.scores <- lofactor(scale(similarityData[which(complete.cases(similarityData))]), k=5)
    #   #plot(density(outlier.scores))
    #   outliers <- which(complete.cases(similarityData))[which(outlier.scores > 1.2)]
    #   cat("Outliers:",outliers,fill=T)
    #   data3D$area[outliers] <- NA
    
    print(wireframe(imputeField ~ Time*SliceLocation, data=data3D,
                    shade=T, col.regions = terrain.colors(100), 
                    main=paste("Outliers Removed Id=",plotId), 
                    zlim=zRange, zlab=imputeFieldName))
  
    # Missing imputation (kNN doesnt work with many NAs, caret bag is very slow)
    # anisotropic penalised regression splines
    b1 <- gam(imputeField ~ s(Time,SliceLocation), data=data3D)
    #vis.gam(b1,ticktype="detailed",phi=30,theta=-30) # also nice vizualation
    #title(paste("Missings Imputed Id=",plotId))
    preds <- predict(b1, similarityData)
    #preds <- predict(preProcess(data3D, method="bagImpute"), newdata=data3D)
  
    # only for the NA's
    #data3D[,area := ifelse(is.na(area), preds, area)]
    # or completely smoothing
    data3D[,imputeField := preds]
    
    # In case there's still NA/NaN's left, first do mean by Slice, if still missing, do global
    data3D[,imputeField := ifelse(is.na(imputeField), mean(imputeField, na.rm=T), imputeField),by=Slice] 
    data3D[,imputeField := ifelse(is.na(imputeField), mean(imputeField, na.rm=T), imputeField)]          
    
    print(wireframe(imputeField ~ Time*SliceLocation, data=data3D,
                    shade=T, col.regions = terrain.colors(100), 
                    main=paste("Missings Imputed Id=",plotId), 
                    zlim=zRange, zlab=imputeFieldName))
    
    # copy imputed and smoothed data back to imageData
    for (i in seq(nrow(data3D))) {
      imageData[Id == data3D[i]$Id & Slice == data3D[i]$Slice & Time == data3D[i]$Time, 
                c(imputeFieldName) := list(data3D[i]$imputeField) ]
    }
    imageData[Id == data3D[i]$Id, c("RatioOutlier","RatioMissing") := list(RatioOutlier + outlierRatio/length(imputeFieldNames),
                                                                           RatioMissing + missingRatio/length(imputeFieldNames))]
  }
}

# for later use
# write.csv(imageData, 'imageData-imputed.csv', row.names=F)

#
# Plot some graphs
#

print(ggplot(filter(imageData, !is.na(pLV) & Id %in% sampleIds), aes(x=SliceLocation, y=area, colour=factor(Id)))+geom_line()+
        ggtitle("Segment area over Slice"))
print(ggplot(filter(imageData, !is.na(pLV) & Id %in% sampleIds), aes(x=Time, y=area, colour=factor(Id)))+geom_boxplot()+
        ggtitle("Segment area over Time"))

# Aggregate up to Time level
timeData <- group_by(imageData, Id, Time) %>%
  dplyr::summarise(volume = sum(SliceThickness*area, na.rm=T),
                   lvConfidence = mean(pLV, na.rm=T),
                   segmentMissingRatio = mean(RatioMissing, na.rm=T),
                   volumeEllipse = sum(SliceThickness*area.ellipse, na.rm=T),
                   volumeMax  = sum(SliceThickness*pi*radius.max^2, na.rm=T),
                   volumeMin  = sum(SliceThickness*pi*radius.min^2, na.rm=T),
                   volumeMean = sum(SliceThickness*pi*radius.mean^2, na.rm=T),
                   
                   isLV = any(isLV))
print(ggplot(filter(timeData, Id %in% sampleIds), aes(x=Time, y=volume, colour=factor(Id)))+geom_line()+geom_point()+
        ggtitle("Volume over Time"))

cat("Total",nrow(timeData),"images, of which",nrow(filter(timeData,isLV)),"have a detected LV",fill=T)
# poorly segmented slices: filter(timeData, is.na(isLV), with=T)
timeData <- filter(timeData, !is.na(isLV)) # keep only the ones with an LV

# Now, aggregate up to Id
caseList <- getIdList(playlist=imageList)
caseData <- left_join(caseList, group_by(timeData, Id) %>%
                        dplyr::summarise(
                          max_volume = max(volume, na.rm=T),
                          min_volume = min(volume, na.rm=T),
                          sd_volume  = sd(volume, na.rm=T),
                          
                          lvConfidence = mean(lvConfidence, na.rm=T),
                          segmentMissingRatio = mean(segmentMissingRatio, na.rm=T),
                          
                          max_volumeEllipse = max(volumeEllipse, na.rm=T),
                          min_volumeEllipse = min(volumeEllipse, na.rm=T),
                          
                          max_volumeMax = max(volumeMax, na.rm=T),
                          min_volumeMax = min(volumeMax, na.rm=T),
                          
                          max_volumeMin = max(volumeMin, na.rm=T),
                          min_volumeMin = min(volumeMin, na.rm=T),
                          
                          max_volumeMean = max(volumeMean, na.rm=T),
                          min_volumeMean = min(volumeMean, na.rm=T),
                          
                          isLV = any(isLV)), 
                      by="Id")
cat("Total",nrow(caseData),"cases, of which",nrow(filter(caseData,isLV)),"have a detected LV",fill=T)

# Some quick summaries on the data quality
print(ggplot(data=caseData, aes(x=segmentMissingRatio, colour=PatientsSex))+geom_density())
print(ggplot(data=caseData, aes(x=lvConfidence, colour=PatientsSex))+geom_density())
print(ggplot(data=caseData, aes(x=segmentMissingRatio,y=lvConfidence, colour=PatientsSex))+geom_point())

# Train data
caseData <- left_join(caseData, trainVolumes, by="Id")

# All cases (dev/train/test) with engineered extra features
casePredictSet <- select(caseData, 
                         -Id, -Dataset, -ImgType, -isLV,
                         -lvConfidence, -segmentMissingRatio)
# casePredictSet <- mutate(casePredictSet, # extra vars
#                          maxVolume2 = max_volumeEllipse^2,
#                          minVolume2 = max_volumeEllipse^2,
#                          maxVolumeSlice = max_volumeEllipse*SliceCount,
#                          minVolumeSlice = max_volumeEllipse*SliceCount)

### Build model (caret)

casePredictSetTrain <- filter(casePredictSet, 
                              !is.na(casePredictSet$Systole),
                              !is.na(casePredictSet$Diastole))

# Run repeatedly to get a distribution of the predictions and a validation error indication
nSamples <- 500
doTuning <- F
rmse_systole <- rep(NA, nSamples)
rmse_diastole <- rep(NA, nSamples)
for (i in seq(nSamples)) {
  casePredictValidationRows <- sample.int(nrow(casePredictSetTrain), 
                                          validationPercentage*nrow(casePredictSetTrain))
  casePredictSetTrainVal <- casePredictSetTrain[casePredictValidationRows,]  # for reporting error
  casePredictSetTrainDev <- casePredictSetTrain[-casePredictValidationRows,] # for training the models
  
  # Predict with Caret
  if (doTuning) {
    fitControl <- trainControl(
      method = "repeatedcv", # 10-fold repeated CV
      number = 5,
      repeats = 2)
    gbmGrid <-  expand.grid(interaction.depth = 3, # 3
                            n.trees = (1:10)*5, # 50
                            shrinkage = seq(0.05,0.2,by=0.05),
                            n.minobsinnode = seq(10,20,by=5))
    systole_model <- train(Systole ~ ., data = select(casePredictSetTrainDev, -Diastole), 
                           method = "gbm", trControl = fitControl, verbose=F, tuneGrid=gbmGrid)
    print(ggplot(systole_model))
    print(ggplot(varImp(systole_model)))
    print(systole_model$bestTune)
    diastole_model <- train(Diastole ~ ., data = select(casePredictSetTrainDev, -Systole), 
                            method = "gbm", trControl = fitControl, verbose=F, tuneGrid=gbmGrid)
    print(ggplot(diastole_model))
    print(ggplot(varImp(diastole_model)))
    print(diastole_model$bestTune)
  } else {
    fixedTuningParams <- data.frame(interaction.depth = 3,
                                    n.trees = 50,
                                    shrinkage = 0.1,
                                    n.minobsinnode = 10)
    systole_model <- train(Systole ~ ., data = select(casePredictSetTrainDev, -Diastole), 
                           method = "gbm", trControl = trainControl(method = "none"), verbose=F, 
                           preProcess="knnImpute",
                           tuneGrid=fixedTuningParams)
    diastole_model <- train(Diastole ~ ., data = select(casePredictSetTrainDev, -Systole), 
                            method = "gbm", trControl = trainControl(method = "none"), verbose=F, 
                            preProcess="knnImpute",
                            tuneGrid=fixedTuningParams)
  }  
  preds_systole_one_sample <- predict(systole_model, newdata=casePredictSet, na.action="na.include")
  cat(i,head(preds_systole_one_sample),fill=T)
  preds_diastole_one_sample <- predict(diastole_model, newdata=casePredictSet, na.action="na.include")
  cat(i,head(preds_diastole_one_sample),fill=T)
  
  if (i==1) {
    preds_systole <- matrix(data = preds_systole_one_sample, ncol = nrow(casePredictSet), nrow = 1, byrow=F)
    preds_diastole <- matrix(data = preds_diastole_one_sample, ncol = nrow(casePredictSet), nrow = 1, byrow=F)
  } else {
    preds_systole <- rbind(preds_systole, preds_systole_one_sample)
    preds_diastole <- rbind(preds_diastole, preds_diastole_one_sample)
  }
  
  # check predictions on val set
  val_preds_systole <- predict(systole_model, newdata=casePredictSetTrainVal, na.action="na.include")
  rmse_systole[i] <- sqrt(mean((val_preds_systole-casePredictSetTrainVal$Systole)^2,na.rm=TRUE))
  val_preds_diastole <- predict(diastole_model, newdata=casePredictSetTrainVal, na.action="na.include")
  rmse_diastole[i] <- sqrt(mean((val_preds_diastole-casePredictSetTrainVal$Diastole)^2,na.rm=TRUE))
}
dimnames(preds_systole) <- list(1:nSamples,caseData$Id)
dimnames(preds_diastole) <- list(1:nSamples,caseData$Id)
cat("Average error on Systole on validation set:", mean(rmse_systole),fill=T)
cat("Average error on Diastole on validation set:", mean(rmse_diastole),fill=T)
print(ggplot(gather(data.frame(rmse_systole, rmse_diastole),measure,RMSE), aes(x=RMSE, colour=measure))+geom_density()+ggtitle("RMSE on Validation Set"))

# Cumulative probabilities, for all cases
probs <- matrix(nrow = 2*nrow(casePredictSet), ncol = MAXVOLUME)
for (i in seq(nrow(casePredictSet))) {
  probs[2*i-1,] <- sapply(seq(MAXVOLUME), function(v) { return(sum(preds_diastole[,i] < v)/nSamples) })
  probs[2*i,] <- sapply(seq(MAXVOLUME), function(v) { return(sum(preds_systole[,i] < v)/nSamples) })
}
probs <- data.frame(Id = as.vector(sapply(caseData$Id,function(n){paste(n,c('Diastole','Systole'),sep="_")})), probs)
names(probs) <- c('Id', paste("P",0:(MAXVOLUME-1),sep=""))

# Submit results
submitRange <- c(2*(which(caseData$Dataset != "train"))-1, 2*(which(caseData$Dataset != "train")))
cat("Creating submission scores for range",range(submitRange),fill=T)
write.csv(probs[min(submitRange):max(submitRange),], "submission.csv", row.names=F)

# Plot a few of the results
ds_plot <- gather(probs[which(caseData$Id %in% sampleIds),],Volume,Density,-Id)
ds_plot$Volume <- as.integer(gsub("P(.*)","\\1",ds_plot$Volume))
ds_plot$Patient <- factor(gsub("(.*)_(.*)","\\1",ds_plot$Id))
ds_plot$Phase <- factor(gsub("(.*)_(.*)","\\2",ds_plot$Id))
print(ggplot(data=ds_plot, aes(x=Volume, y=Density, colour=Patient, linetype=Phase))+
        geom_line(alpha=0.5)+
        ggtitle("Submissions"))

# Report on results
cat("Correlations on",sum((caseData$Dataset == "train")),"cases:",fill=T)
diastole_mean <- sapply(as.data.frame(preds_diastole[,which(caseData$Dataset == "train")]), mean)
systole_mean <- sapply(as.data.frame(preds_systole[,which(caseData$Dataset == "train")]), mean)
print(cor(caseData$Systole[which(caseData$Dataset == "train")], systole_mean, use="complete.obs"))
print(cor(caseData$Diastole[which(caseData$Dataset == "train")], diastole_mean, use="complete.obs"))

# Report on Kaggle's CRPS score
validateRange <- c(2*(which(caseData$Dataset == "train"))-1, 2*(which(caseData$Dataset == "train")))
trainProbabilities <- probs[min(validateRange):max(validateRange),]
crps <- 0
for (i in seq(nrow(trainVolumes))) {
  probs1 <- as.vector(as.matrix(trainProbabilities[2*i-1,2:ncol(trainProbabilities)]))
  truth1 <- ifelse(seq(MAXVOLUME) >= trainVolumes$Diastole[i], 1, 0)
  
  probs2 <- as.vector(as.matrix(trainProbabilities[2*i,2:ncol(trainProbabilities)]))
  truth2 <- ifelse(seq(MAXVOLUME) >= trainVolumes$Systole[i], 1, 0)
  
  crps <- crps + sum((probs1 - truth1)^2, na.rm=T) + sum((probs2 - truth2)^2, na.rm=T)
}
crps <- crps/nrow(trainProbabilities)/MAXVOLUME
cat("CRPS score on train set:", crps,fill=T)

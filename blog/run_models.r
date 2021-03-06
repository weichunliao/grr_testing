library(data.table)

library(xgboost)
library(FNN)
library(glmnet)
library(ranger)
library(e1071)

library(baeirGPR)
#####
rmse <- function(y_hat, y, method = "") {
  out <- sqrt(mean((y - y_hat)^2))
  cat(method,"rmse = ", out, "\n")
  return(out)
}
#####
# source('~/Desktop/baeirGPR/R/call_by_user.R')
# Rcpp::sourceCpp('~/Desktop/baeirGPR/src/matprod.cpp')
# source('~/Desktop/baeirGPR/R/gpr.R')
# source('~/Desktop/baeirGPR/R/local_gpr.R')
# source('~/Desktop/baeirGPR/R/gpr_tuning.R')
# source('~/Desktop/baeirGPR/R/boosting_gpr.R')
#####
# task: predict the number of comments iin the next 24 hours
# V281: The target: the number of comments in the next 24 hours

# step0. load data and set col names
setwd("~/Desktop/gpr_testing/blog/")
ds_train <- fread("./BlogFeedback-Train2.csv")
ds_test <- fread("./BlogFeedback-Test2.csv")
ncol(ds_train)
setnames(ds_train, c(paste('x', 1:271, sep=''), 'y'))
setnames(ds_test, c(paste('x', 1:271, sep=''), 'y'))
ds_train = as.data.frame(ds_train)
ds_test = as.data.frame(ds_test)

#########################################################################
tmp_train <- as.data.frame(ds_train)
tmp_test <- as.data.frame(ds_test)

# step1. mean shift
mean_shift = mean(tmp_train$y)
tmp_train$y = tmp_train$y - mean_shift
tmp_test$y = tmp_test$y - mean_shift

# step2. normalize continuous var
for (i in c(1:54, 270, 271)){
  m_train <- mean(tmp_train[,i])
  std_train <- sd(tmp_train[,i])

  tmp_train[,i] <- (tmp_train[,i] - m_train)/std_train
  tmp_test[,i] <- (tmp_test[,i] - m_train)/std_train
}

# step3. remove linear dependent col
# library(caret)
# rm_col_idx = findLinearCombos(tmp_train[,-272])$remove
rm_col_idx = c(16,  47,  52,  65,  68,  72,  73,  86,  89, 122, 124, 141, 148, 153, 158, 161, 164, 171,
               182, 190, 192, 204, 228, 235, 242 ,268)
ds2_train = tmp_train[, -rm_col_idx]
ds2_test = tmp_test[, -rm_col_idx]
ncol(ds2_train)

ds_train = ds_train[, -rm_col_idx]
ds_test = ds_test[, -rm_col_idx]

# step.4 model matrix
ds2_train_x <- model.matrix(y~.-1, ds2_train)
ds2_train_y <- as.matrix(ds2_train$y)

ds2_test_x <- model.matrix(y~.-1, ds2_test)
ds2_test_y <- as.matrix(ds2_test$y)

### for baeirGPR
# step5. tuning kernel param
t_size <- 1000
t_idx <- sample(nrow(ds2_train_x), t_size)
ds_tune_y <- as.matrix(ds2_train_y[t_idx,])
kern_param1 = gpr_tune(as.matrix(ds2_train_x[t_idx,]), ds_tune_y, kernelname = "rbf",
                       optim_report = 5, optim_ard_report = 5,
                       ARD = T, optim_ard_max = 50)
t_size <- 5000
t_idx <- sample(nrow(ds2_train_x), t_size)
ds_tune_y <- as.matrix(ds2_train_y[t_idx,])
kern_param1 = gpr_tune(ds2_train_x[t_idx,], ds_tune_y, kernelname = "rbf",
                       optim_report = 5, optim_ard_report = 5,
                       ARD = T, optim_ard_max = 50, init_betainv = kern_param1$betainv,
                       init_theta = kern_param1$thetarel)
saveRDS(kern_param1, "kern_param1.rds")
# ==================== saveRDS = "blog1.rdata" ========================== #
kern_param1 = readRDS('./kern_param2.rds')
bsize = 500
nmodel = 500
update_k = 50
session_pid = Sys.getpid()
cmd_arg = paste('pidstat \\-r \\-t 60 \\-p', session_pid, sep = ' ')
system(paste(cmd_arg, '> gbm2_bsize500_nmodel500.txt &'))
t1=system.time(gbm_model1 <- gbm_train(ds2_train_x, ds2_train_y, ds2_test_x, ds2_test_y, pred_method = "2",
                                       n_model = nmodel, batch_size = bsize, lr = 0.01, tune_param = TRUE,
                                       update_kparam_tiems = update_k, decay_lr = 0.9,
                                       kname = kern_param1$kernelname, ktheta = kern_param1$thetarel,
                                       kbetainv = kern_param1$betainv))
system(paste("kill $(ps aux | grep -i '", cmd_arg ,"' | awk -F' ' '{ print $2 }')", sep=''))
cat(" baeirGPR rmse =", tail(gbm_model1$test_rmse))
t1
cat("min baeirGPR rmse =", min(gbm_model1$test_rmse))

bsize = 3000
nmodel = 500
update_k = 50
lr = 0.01
session_pid = Sys.getpid()
cmd_arg = paste('pidstat \\-r \\-t 60 \\-p', session_pid, sep = ' ')
system(paste(cmd_arg, '> gbm3_bsize3000_nmodel500.txt &'))
t2=system.time(gbm_model2 <- gbm_train(ds2_train_x, ds2_train_y, ds2_test_x, ds2_test_y, pred_method = "3",
                                       n_model = nmodel, batch_size = bsize, lr = lr, tune_param = FALSE,
                                       update_kparam_tiems = update_k,
                                       kname = kern_param1$kernelname, ktheta = kern_param1$thetarel,
                                       kbetainv = kern_param1$betainv))
system(paste("kill $(ps aux | grep -i '", cmd_arg ,"' | awk -F' ' '{ print $2 }')", sep=''))

# cat(" baeirGPR rmse =", tail(gbm_model2$test_rmse))


session_pid = Sys.getpid()
cmd_arg = paste('pidstat \\-r \\-t 60 \\-p', session_pid, sep = ' ')
system(paste(cmd_arg, '> sr_bsize2000_nmodel500.txt &'))
t3=system.time(gbm_model3 <- gbm_train(ds2_train_x, ds2_train_y, ds2_test_x, ds2_test_y, pred_method = "gbm_sr",
                                       n_model = nmodel, batch_size = bsize, lr = 0.01, tune_param = TRUE,
                                       update_kparam_tiems = update_k,
                                       kname = "gaussiandotrel", ktheta = kern_param1$thetarel,
                                       kbetainv = kern_param1$betainv))
system(paste("kill $(ps aux | grep -i '", cmd_arg ,"' | awk -F' ' '{ print $2 }')", sep=''))
# cat(" baeirGPR rmse =", tail(gbm_model3$test_rmse))

# ols
##### > sum(is.na(lm.fit$coefficients))
##### [1] 27
# library(caret)
# rm_col_idx = findLinearCombos(ds2_train_x)$remove
lm.fit = lm(y~.,data = ds2_train)
# lm.fit$coefficients[names(c(which(is.na(lm.fit$coefficients), arr.ind=1)))] = 0
pred_ols = predict(lm.fit, newdata = as.data.frame(ds2_test_x))
rmse_ols <- rmse(pred_ols, ds2_test_y, "ols")

# xgboost
tmp_xgb <- xgboost(data = data.matrix(ds2_train_x),
                   label = ds2_train_y,
                   eta = 0.05,
                   max_depth = 9,
                   nround = 100,
                   subsample = 0.3,
                   colsample_bytree = 1,
                   seed = 1
)
pred_xgb <- predict(tmp_xgb, data.matrix(ds2_test_x))
rmse_xgb <- rmse(pred_xgb, ds2_test_y, "xgboost")

# try kNN
pred_knn <- knn.reg(ds2_train_x, ds2_test_x, ds2_train_y, k = 14)$pred
rmse_knn <- rmse(pred_knn, ds2_test_y, "knn")

# try LASSO
mdl_lasso = cv.glmnet(ds2_train_x, ds2_train_y, family = "gaussian", alpha = 1)
pred_lasso = predict(mdl_lasso, newx = ds2_test_x)
rmse(pred_lasso, ds2_test_y, "LASSO")

# try RIDGE
# mdl_ridge = cv.glmnet(data.matrix(ds2_train_x), data.matrix(ds2_train_y),
#                       family = "gaussian", alpha = 0, lambda.min.ratio=0.0001)
lambdas <- 10^seq(1, -1, by = -0.001)
mdl_ridge = cv.glmnet(data.matrix(ds2_train_x), data.matrix(ds2_train_y),
                      family = "gaussian", alpha = 0, lambda = lambdas)
pred_ridge = predict(mdl_ridge, newx = data.matrix(ds2_test_x))
rmse(pred_ridge, ds2_test_y, "RIDGE")

# try random forest
# mdl_rf = ranger(y ~ ., data = ds_train, num.trees = 200, mtry = 35, write.forest = T)
# pred_rf = predict(mdl_rf, ds_test[,-272])
# pred_rf2 = pred_rf$predictions
# rmse(pred_rf2, ds_test$y, "random forest")

mdl_rf = ranger(y ~ ., data = ds2_train, num.trees = 1000, mtry = 120, write.forest = T)
pred_rf = predict(mdl_rf, ds2_test[,-246])
pred_rf2 = pred_rf$predictions
rmse(pred_rf2, ds2_test_y, "random forest")

# try svr ###########################
#  linear
mdl_svr = svm(y~., ds2_train, kernel = "linear")
svr.pred = predict(mdl_svr, ds2_test_x)
rmse_svr = rmse(svr.pred, ds2_test_y, "svr linear")

# poly
mdl_svr = svm(y~., ds2_train, kernel = "polynomial", degree = 3)
svr.pred = predict(mdl_svr, ds2_test_x)
rmse_svr = rmse(svr.pred, ds2_test_y, "svr poly")

# rbf
mdl_svr = tune.svm(y~., data = ds2_train, kernel = "radial", gamma = 2^c(-8:0), cost = 2^c(-4:4))
svr.pred = predict(mdl_svr$best.model, ds2_test_x)
rmse_svr = rmse(svr.pred, ds2_test_y, "svr rbf")

######





# full gpr
gpr_model1 <- traintraintrain(ds2_train_x, ds2_train_y, pred_method = "cg_direct_lm",
                              kname = kern_param1$kernelname, ktheta = kern_param1$thetarel,
                              kbetainv = kern_param1$betainv, ncpu = -1, srsize = NULL,
                              clus_size = NULL)
gpr_pred1 <- gpr_fit(ds2_test_x, ds2_train_x, gpr_model1) + mean_shift
rmse_fullGPR <- rmse(gpr_pred1, ds_test_y, "full gpr")



# ############# for vw ##################################################
#
# parse_line <- function(i_row) {
#   f_list <- paste(paste(names(i_row), i_row, sep  = ":"))
#   target_value <- paste(i_row[281], "|", collapse = " ")
#   feature_value <- paste(f_list[1:280], collapse = " ")
#   temp <- paste(target_value, feature_value, sep = " ", collapse = "")
#   return (temp)
# }
#
# tmp = ds_train
# tmp_test = ds_test
# output_form = apply(tmp, 1, function(x) parse_line(x))
# output_form_test = apply(tmp_test, 1, function(x) parse_line(x))
#
# fileConn<-file("vw_data.train")
# writeLines(output_form, fileConn)
# close(fileConn)
#
# fileConn<-file("vw_data.test")
# writeLines(output_form_test, fileConn)
# close(fileConn)
#
# fileConn<-file("vw_data2.test")
# writeLines(gsub(".*\\|", "|", output_form_test), fileConn)
# close(fileConn)
#
#


# https://machinelearningmastery.com/feature-selection-with-the-caret-r-package/



# ensure the results are repeatable
set.seed(7)
# load the library
library(mlbench)
library(caret)
# load the data
# data(PimaIndiansDiabetes)
# define the control using a random forest selection function
control <- rfeControl(functions=rfFuncs, method="cv", number=10)
# run the RFE algorithm
results <- rfe(ds2_train_x[1:1000,], ds2_train_y[1:1000,], sizes=c(1:49), rfeControl=control)
# summarize the results
print(results)
# list the chosen features
predictors(results)

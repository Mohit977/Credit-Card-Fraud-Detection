
install.packages("tidyverse")
library(tidyverse)
creditcard <- read.csv("C:/Users/Dell-pc/Desktop/Github/Projects/Credit Card Fraud Detection/creditcard.csv")

creditcard %>%
  ggplot(aes(x = Class)) +
  geom_bar(color = "grey", fill = "lightgrey") +
  theme_bw()


summary(creditcard$Time)

# how many seconds are 24 hours
# 1 hr = 60 mins = 60 x 60 s = 3600 s
3600 * 24

# separate transactions by day
creditcard$day <- ifelse(creditcard$Time > 3600 * 24, "day2", "day1")

# make transaction relative to day
creditcard$Time_day <- ifelse(creditcard$day == "day2", creditcard$Time - 86400, creditcard$Time)

summary(creditcard[creditcard$day == "day1", ]$Time_day)

summary(creditcard[creditcard$day == "day2", ]$Time_day)

# bin transactions according to time of day
creditcard$Time <- as.factor(ifelse(creditcard$Time_day <= 38138, "gr1", # mean 1st Qu.
                                    ifelse(creditcard$Time_day <= 52327, "gr2", # mean mean
                                           ifelse(creditcard$Time_day <= 69580, "gr3", # mean 3rd Qu
                                                  "gr4"))))
creditcard %>%
  ggplot(aes(x = day)) +
  geom_bar(color = "grey", fill = "lightgrey") +
  theme_bw()

#removing the time bin
creditcard <- select(creditcard, -Time_day, -day)

# convert class variable to factor
creditcard$Class <- factor(creditcard$Class)


creditcard %>%
  ggplot(aes(x = Time)) +
  geom_bar(color = "grey", fill = "lightgrey") +
  theme_bw() +
  facet_wrap( ~ Class, scales = "free", ncol = 2)

summary(creditcard[creditcard$Class == "0", ]$Amount)

summary(creditcard[creditcard$Class == "1", ]$Amount)

creditcard %>%
  ggplot(aes(x = Amount)) +
  geom_histogram(color = "grey", fill = "lightgrey", bins = 50) +
  theme_bw() +
  facet_wrap( ~ Class, scales = "free", ncol = 2)

###############################
#Modeling

install.packages('h2o')
library(h2o)
h2o.init(ip = "localhost", start = TRUE) #Making connection

# convert data to H2OFrame
creditcard_hf <- as.h2o(creditcard)

#splitting the data
splits <- h2o.splitFrame(creditcard_hf, 
                         ratios = c(0.4, 0.4), 
                         seed = 42)

train_unsupervised  <- splits[[1]]
train_supervised  <- splits[[2]]
test <- splits[[3]]

response <- "Class"
features <- setdiff(colnames(train_unsupervised), response)


model_nn <- h2o.deeplearning(x = features, 
                             training_frame = train_unsupervised,
                             model_id = "model_nn",
                             autoencoder = TRUE,
                             reproducible = TRUE, #slow - turn off for real problems
                             ignore_const_cols = FALSE,
                             seed = 42,
                             hidden = c(10, 2, 10), 
                             epochs = 100,
                             activation = "Tanh")

#Saving the model
h2o.saveModel(model_nn, path="model_nn", force = TRUE)
model_nn <- h2o.loadModel("model_nn")
model_nn


#Convert to autoencoded representation
test_autoenc <- h2o.predict(model_nn, test)

#Dimension reduction with hidden layer
train_features <- h2o.deepfeatures(model_nn, train_unsupervised, layer = 2) %>%
  as.data.frame() %>%
  mutate(Class = as.vector(train_unsupervised[, 31]))

ggplot(train_features, aes(x = DF.L2.C1, y = DF.L2.C2, color = Class)) +
  geom_point(alpha = 0.1)

# let's take the third hidden layer
train_features <- h2o.deepfeatures(model_nn, train_unsupervised, layer = 3) %>%
  as.data.frame() %>%
  mutate(Class = as.factor(as.vector(train_unsupervised[, 31]))) %>%
  as.h2o()

features_dim <- setdiff(colnames(train_features), response)

model_nn_dim <- h2o.deeplearning(y = response,
                                 x = features_dim,
                                 training_frame = train_features,
                                 reproducible = TRUE, #slow - turn off for real problems
                                 balance_classes = TRUE,
                                 ignore_const_cols = FALSE,
                                 seed = 42,
                                 hidden = c(10, 2, 10), 
                                 epochs = 100,
                                 activation = "Tanh")

h2o.saveModel(model_nn_dim, path="model_nn_dim", force = TRUE)

model_nn_dim <- h2o.loadModel("model_nn_dim/DeepLearning_model_R_1493574057843_49")
model_nn_dim

test_dim <- h2o.deepfeatures(model_nn, test, layer = 3)


h2o.predict(model_nn_dim, test_dim) %>%
  as.data.frame() %>%
  mutate(actual = as.vector(test[, 31])) %>%
  group_by(actual, predict) %>%
  summarise(n = n()) %>%
  mutate(freq = n / sum(n))


#Anomaly detection
anomaly <- h2o.anomaly(model_nn, test) %>%
  as.data.frame() %>%
  tibble::rownames_to_column() %>%
  mutate(Class = as.vector(test[, 31]))

mean_mse <- anomaly %>%
  group_by(Class) %>%
  summarise(mean = mean(Reconstruction.MSE))

ggplot(anomaly, aes(x = as.numeric(rowname), y = Reconstruction.MSE, color = as.factor(Class))) +
  geom_point(alpha = 0.3) +
  geom_hline(data = mean_mse, aes(yintercept = mean, color = Class)) +
  scale_color_brewer(palette = "Set1") +
  labs(x = "instance number",
       color = "Class")


anomaly <- anomaly %>%
  mutate(outlier = ifelse(Reconstruction.MSE > 0.02, "outlier", "no_outlier"))

anomaly %>%
  group_by(Class, outlier) %>%
  summarise(n = n()) %>%
  mutate(freq = n / sum(n)) 


#Pre-trained superwized model

model_nn_2 <- h2o.deeplearning(y = response,
                               x = features,
                               training_frame = train_supervised,
                               pretrained_autoencoder  = "model_nn",
                               reproducible = TRUE, #slow - turn off for real problems
                               balance_classes = TRUE,
                               ignore_const_cols = FALSE,
                               seed = 42,
                               hidden = c(10, 2, 10), 
                               epochs = 100,
                               activation = "Tanh")

h2o.saveModel(model_nn_2, path="model_nn_2", force = TRUE)

model_nn_2 <- h2o.loadModel("model_nn_2/DeepLearning_model_R_1493574057843_9")
model_nn_2

#predicting
pred <- as.data.frame(h2o.predict(object = model_nn_2, newdata = test)) %>%
  mutate(actual = as.vector(test[, 31]))

pred %>%
  group_by(actual, predict) %>%
  summarise(n = n()) %>%
  mutate(freq = n / sum(n)) 


pred %>%
  ggplot(aes(x = actual, fill = predict)) +
  geom_bar() +
  theme_bw() +
  scale_fill_brewer(palette = "Set1") +
  facet_wrap( ~ actual, scales = "free", ncol = 2)

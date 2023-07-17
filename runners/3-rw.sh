#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=48
#SBATCH -p sequana_gpu_shared
#SBATCH -J tr-aff
#SBATCH -o /scratch/lerdl/lucas.david/logs/aff-%j.out
#SBATCH --time=24:00:00

# Copyright 2023 Lucas Oliveira David
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Random Walk.
#

ENV=sdumont
WORK_DIR=$SCRATCH/PuzzleCAM
# ENV=local
# WORK_DIR=/home/ldavid/workspace/repos/research/pnoc

# Dataset
# DATASET=voc12  # Pascal VOC 2012
# DATASET=coco14  # MS COCO 2014
DATASET=deepglobe # DeepGlobe Land Cover Classification

. $WORK_DIR/runners/config/env.sh
. $WORK_DIR/runners/config/dataset.sh

cd $WORK_DIR
export PYTHONPATH=$(pwd)

# Architecture
ARCHITECTURE=resnest269
ARCH=rs269
BATCH_SIZE=32
LR=0.1

# Infrastructure
MIXED_PRECISION=true # false

rw_make_affinity_labels() {
  echo "=================================================================="
  echo "[rw make affinity labels] started at $(date +'%Y-%m-%d %H:%M:%S')."
  echo "=================================================================="

  $PY scripts/rw/rw_make_affinity_labels.py \
    --tag $AFF_LABELS_TAG \
    --dataset $DATASET \
    --domain $DOMAIN \
    --fg_threshold $FG \
    --bg_threshold $BG \
    --crf_t $CRF_T \
    --crf_gt_prob $CRF_GT \
    --cams_dir $CAMS_DIR \
    --sal_dir $SAL_DIR \
    --data_dir $DATA_DIR \
    --num_workers $WORKERS_INFER
}

rw_training() {
  echo "=================================================================="
  echo "[rw training] started at $(date +'%Y-%m-%d %H:%M:%S')."
  echo "=================================================================="

  CUDA_VISIBLE_DEVICES=$DEVICES \
    WANDB_TAGS="$DATASET,$ARCH,rw" \
    $PY scripts/rw/train_affinity.py \
    --architecture $ARCHITECTURE \
    --tag $AFF_TAG \
    --batch_size $BATCH_SIZE \
    --image_size $IMAGE_SIZE \
    --min_image_size $MIN_IMAGE_SIZE \
    --max_image_size $MAX_IMAGE_SIZE \
    --dataset $DATASET \
    --lr $LR \
    --label_dir $AFF_LABELS_DIR \
    --data_dir $DATA_DIR \
    --num_workers $WORKERS_TRAIN
}

rw_inference() {
  echo "=================================================================="
  echo "[rw inference $DOMAIN] started at $(date +'%Y-%m-%d %H:%M:%S')."
  echo "=================================================================="

  CUDA_VISIBLE_DEVICES=$DEVICES \
    $PY scripts/rw/inference.py \
    --architecture $ARCHITECTURE \
    --image_size $IMAGE_SIZE \
    --model_name $AFF_TAG \
    --cam_dir $CAMS_DIR \
    --domain $DOMAIN \
    --beta $RW_BETA \
    --exp_times $RW_EXP \
    --mixed_precision $MIXED_PRECISION \
    --dataset $DATASET \
    --data_dir $DATA_DIR
}

make_pseudo_labels() {
  $PY scripts/rw/make_pseudo_labels.py \
    --experiment_name $RW_MASKS \
    --domain $DOMAIN \
    --threshold $THRESHOLD \
    --crf_t $CRF_T \
    --crf_gt_prob $CRF_GT \
    --data_dir $DATA_DIR \
    --num_workers $WORKERS_INFER
}

run_evaluation() {
  CUDA_VISIBLE_DEVICES="" \
    WANDB_RUN_GROUP="$W_GROUP" \
    WANDB_TAGS="$W_TAGS" \
    $PY scripts/evaluate.py \
    --experiment_name $RW_MASKS \
    --dataset $DATASET \
    --domain $DOMAIN \
    --data_dir $DATA_DIR \
    --min_th $MIN_TH \
    --max_th $MAX_TH \
    --crf_t $CRF_T \
    --crf_gt_prob $CRF_GT \
    --num_workers $WORKERS_INFER
}

## 3.1 Make Affinity Labels
##
# PRIORS_TAG=ra-oc-p-poc-pnoc-avg
PRIORS_TAG=ra-oc-p-poc-pnoc-learned-a0.25
W_GROUP=$DATASET-$PRIORS_TAG

CAMS_DIR=./experiments/predictions/ensemble/$PRIORS_TAG
SAL_DIR=./experiments/predictions/saliency/voc12-pn@ccamh-rs269@$PRIORS_TAG
FG=0.30
BG=0.10
CRF_T=10
CRF_GT=0.7

AFF_LABELS_TAG=rw/$DATASET-an@ccamh@$PRIORS_TAG@crf$CRF_T-gt$CRF_GT
rw_make_affinity_labels

## 3.2. Affinity Net Train
##
AFF_TAG=rw/$DATASET-an@ccamh@$PRIORS_TAG
AFF_LABELS_DIR=./experiments/predictions/$AFF_LABELS_TAG@aff_fg="$FG"_bg="$BG"
rw_training

## 3.3. Affinity Net Inference
##
RW_BETA=10
RW_EXP=8

DOMAIN=train_aug # train2014 for COCO14
rw_inference
DOMAIN=val
rw_inference

CRF_T=1
MIN_TH=0.05
MAX_TH=0.81

DOMAIN=train
RW_MASKS=$AFF_TAG@$DOMAIN@beta=$RW_BETA@exp_times=$RW_EXP@rw
W_TAGS="$DATASET,domain:$DOMAIN,$ARCH,ensemble,ccamh,rw,crf:$CRF_T-$CRF_GT"
run_evaluation

DOMAIN=val
RW_MASKS=$AFF_TAG@$DOMAIN@beta=$RW_BETA@exp_times=$RW_EXP@rw
W_TAGS="$DATASET,domain:$DOMAIN,$ARCH,ensemble,ccamh,rw,crf:$CRF_T-$CRF_GT"
run_evaluation

## 3.4 Make Pseudo Masks
##

PRIORS_TAG=ra-oc-p-poc-pnoc-avg
# PRIORS_TAG=ra-oc-p-poc-pnoc-learned-a0.25

THRESHOLD=0.3
CRF_T=1
CRF_GT=0.9

AFF_TAG=rw/$DATASET-an@ccamh@$PRIORS_TAG

DOMAIN=$DOMAIN_TRAIN RW_MASKS=$AFF_TAG@train@beta=10@exp_times=8@rw make_pseudo_labels
DOMAIN=$DOMAIN_VALID RW_MASKS=$AFF_TAG@val@beta=10@exp_times=8@rw make_pseudo_labels

# Move everything (train/val) into a single folder.
RW_MASKS_DIR=./experiments/predictions/$AFF_TAG@beta=10@exp_times=8@rw@crf=$CRF_T
mv ./experiments/predictions/$AFF_TAG@train@beta=10@exp_times=8@rw@crf=$CRF_T $RW_MASKS_DIR
mv ./experiments/predictions/$AFF_TAG@val@beta=10@exp_times=8@rw@crf=$CRF_T/* $RW_MASKS_DIR/
rm -r ./experiments/predictions/$AFF_TAG@val@beta=10@exp_times=8@rw@crf=$CRF_T
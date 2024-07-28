#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=48
#SBATCH -p sequana_gpu_shared
#SBATCH -J ss-train
#SBATCH -o /scratch/lerdl/lucas.david/experiments/logs/ss/train-%j.out
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
# Train a model to perform multilabel classification over a WSSS dataset.
#

if [[ "`hostname`" == "sdumont"* ]]; then
  ENV=sdumont
  WORK_DIR=$SCRATCH/single-stage
else
  ENV=local
  WORK_DIR=$HOME/workspace/repos/research/wsss/wsss-csrm
fi

echo "Env:      $ENV"
echo "Work Dir: $WORK_DIR"

# Dataset
# DATASET=voc12  # Pascal VOC 2012
DATASET=coco14  # MS COCO 2014
# DATASET=deepglobe # DeepGlobe Land Cover Classification

. $WORK_DIR/runners/config/env.sh
. $WORK_DIR/runners/config/dataset.sh

export 'PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256'

cd $WORK_DIR
export PYTHONPATH=$(pwd)

# $PIP install --user -r requirements.txt

## Architecture
### Priors
ARCH=rs269
ARCHITECTURE=resnest269
MODE=fix
TRAINABLE_STEM=false
TRAINABLE_STAGE4=true
TRAINABLE_BONE=true
DILATED=false
USE_SAL_HEAD=false
USE_REP_HEAD=true

# Training
OPTIMIZER=sgd  # sgd,lion,adam
LR=0.007
MOMENTUM=0.9
NESTEROV=true
FIRST_EPOCH=0
EPOCHS=15
BATCH=32
ACCUMULATE_STEPS=1

DOMAIN_TRAIN_UNLABELED=$DOMAIN_TRAIN
SAMPLER=default
# SAMPLER=balanced

LR_ALPHA_SCRATCH=10.0
LR_ALPHA_BIAS=1.0
LR_POLY_POWER=0.9
GRAD_MAX_NORM=1.

MIXED_PRECISION=true
PERFORM_VALIDATION=true
PROGRESS=true

## Augmentation
# AUGMENT=none_classmix for DeepGlobe
AUGMENT=classmix
# AUGMENT=colorjitter_cutmix
CUTMIX=0.5
MIXUP=0.5
LABELSMOOTHING=0.1

S2C_MODE=mp
S2C_SIGMA=0.50   # min pixel confidence (conf_p := max_class(prob)_pixel >= S2C_SIGMA)
WARMUP_EPOCHS=1  # min pixel confidence (conf_p := max_class(prob)_pixel >= S2C_SIGMA)
C2S_SIGMA=0.75   # min pixel confidence (conf_p := max_class(prob)_pixel >= S2C_SIGMA)
C2S_FG=0.30
C2S_BG=0.05
C2S_MODE=cam

W_CONTRA=1
W_U=1

CONTRA_LOW_RANK=3
CONTRA_HIGH_RANK=6  # 20

# Evaluation
MIN_TH=0.05
MAX_TH=0.81
CRF_T=10
CRF_GT=0.7
EVAL_MODE=npy
KIND=cams
# KIND=masks
IGNORE_BG_CAM=false


train_reco() {
  echo "=================================================================="
  echo "[train $TAG] started at $(date +'%Y-%m-%d %H:%M:%S')."
  echo "=================================================================="

  WANDB_TAGS="$DATASET,$ARCH,reco,lr:$LR,wd:$WD,ls:$LABELSMOOTHING,b:$BATCH,ac:$ACCUMULATE_STEPS,s2c:$S2C_MODE,c2s:$C2S_MODE,warmup:$WARMUP_EPOCHS" \
    WANDB_RUN_GROUP="$DATASET-$ARCH-reco" \
    CUDA_VISIBLE_DEVICES=$DEVICES \
    PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512 \
    $PY scripts/ss/train_reco.py \
    --tag $TAG \
    --lr $LR \
    --wd $WD \
    --s2c_mode  $S2C_MODE \
    --c2s_mode  $C2S_MODE \
    --c2s_sigma $C2S_SIGMA \
    --s2c_sigma $S2C_SIGMA \
    --warmup_epochs $WARMUP_EPOCHS \
    --optimizer $OPTIMIZER \
    --lr_alpha_scratch $LR_ALPHA_SCRATCH \
    --lr_alpha_bias $LR_ALPHA_BIAS \
    --lr_poly_power $LR_POLY_POWER \
    --momentum $MOMENTUM \
    --nesterov $NESTEROV \
    --grad_max_norm $GRAD_MAX_NORM \
    --batch_size $BATCH \
    --accumulate_steps $ACCUMULATE_STEPS \
    --mixed_precision $MIXED_PRECISION \
    --architecture $ARCHITECTURE \
    --use_sal_head $USE_SAL_HEAD \
    --use_rep_head $USE_REP_HEAD \
    --dilated $DILATED \
    --mode $MODE \
    --trainable-stem $TRAINABLE_STEM \
    --trainable-stage4 $TRAINABLE_STAGE4 \
    --trainable-backbone $TRAINABLE_BONE \
    --image_size $IMAGE_SIZE \
    --min_image_size $MIN_IMAGE_SIZE \
    --max_image_size $MAX_IMAGE_SIZE \
    --augment $AUGMENT \
    --cutmix_prob $CUTMIX \
    --mixup_prob $MIXUP \
    --label_smoothing $LABELSMOOTHING \
    --first_epoch $FIRST_EPOCH \
    --max_epoch $EPOCHS \
    --max_steps $MAX_STEPS \
    --dataset $DATASET \
    --data_dir $DATA_DIR \
    --sampler $SAMPLER \
    --domain_train $DOMAIN_TRAIN \
    --domain_valid $DOMAIN_VALID \
    --progress $PROGRESS \
    --validate $PERFORM_VALIDATION \
    --validate_max_steps $VALIDATE_MAX_STEPS \
    --validate_thresholds $VALIDATE_THRESHOLDS \
    --device $DEVICE \
    --num_workers $WORKERS_TRAIN \
    --restore $RESTORE;
}

train_u2pl() {
  echo "=================================================================="
  echo "[train $TAG] started at $(date +'%Y-%m-%d %H:%M:%S')."
  echo "=================================================================="

  WANDB_TAGS="$DATASET,$ARCH,u2pl,aug:$AUGMENT,lr:$LR,wd:$WD,ls:$LABELSMOOTHING,b:$BATCH,ac:$ACCUMULATE_STEPS,c2s:$C2S_MODE,warmup:$WARMUP_EPOCHS,s:$SAMPLER,rank:$CONTRA_LOW_RANK-$CONTRA_HIGH_RANK" \
    WANDB_RUN_GROUP="$DATASET-$ARCH-u2pl" \
    CUDA_VISIBLE_DEVICES=$DEVICES \
    $PY scripts/ss/train_u2pl.py \
    --tag $TAG \
    --lr $LR \
    --wd $WD \
    --c2s_mode $C2S_MODE \
    --c2s_sigma $C2S_SIGMA \
    --s2c_sigma $S2C_SIGMA \
    --c2s_fg    $C2S_FG \
    --c2s_bg    $C2S_BG \
    --w_contra  $W_CONTRA \
    --contra_low_rank $CONTRA_LOW_RANK \
    --contra_high_rank $CONTRA_HIGH_RANK \
    --w_u       $W_U \
    --warmup_epochs $WARMUP_EPOCHS \
    --optimizer $OPTIMIZER \
    --lr_alpha_scratch $LR_ALPHA_SCRATCH \
    --lr_alpha_bias $LR_ALPHA_BIAS \
    --lr_poly_power $LR_POLY_POWER \
    --momentum $MOMENTUM \
    --nesterov $NESTEROV \
    --grad_max_norm $GRAD_MAX_NORM \
    --batch_size $BATCH \
    --accumulate_steps $ACCUMULATE_STEPS \
    --mixed_precision $MIXED_PRECISION \
    --architecture $ARCHITECTURE \
    --use_sal_head $USE_SAL_HEAD \
    --use_rep_head $USE_REP_HEAD \
    --dilated $DILATED \
    --mode $MODE \
    --trainable-stem $TRAINABLE_STEM \
    --trainable-stage4 $TRAINABLE_STAGE4 \
    --trainable-backbone $TRAINABLE_BONE \
    --image_size $IMAGE_SIZE \
    --min_image_size $MIN_IMAGE_SIZE \
    --max_image_size $MAX_IMAGE_SIZE \
    --augment $AUGMENT \
    --cutmix_prob $CUTMIX \
    --mixup_prob $MIXUP \
    --label_smoothing $LABELSMOOTHING \
    --first_epoch $FIRST_EPOCH \
    --max_epoch $EPOCHS \
    --max_steps $MAX_STEPS \
    --dataset $DATASET \
    --data_dir $DATA_DIR \
    --sampler $SAMPLER \
    --domain_train $DOMAIN_TRAIN \
    --domain_train_unlabeled $DOMAIN_TRAIN_UNLABELED \
    --domain_valid $DOMAIN_VALID \
    --progress $PROGRESS \
    --validate $PERFORM_VALIDATION \
    --validate_max_steps $VALIDATE_MAX_STEPS \
    --validate_thresholds $VALIDATE_THRESHOLDS \
    --device $DEVICE \
    --num_workers $WORKERS_TRAIN \
    --restore $RESTORE;
}

inference() {
  echo "=================================================================="
  echo "[Inference:$TAG] started at $(date +'%Y-%m-%d %H:%M:%S')."
  echo "=================================================================="

  CUDA_VISIBLE_DEVICES=$DEVICES \
    $PY scripts/ss/inference.py \
    --architecture $ARCHITECTURE \
    --dilated $DILATED \
    --use_sal_head $USE_SAL_HEAD \
    --use_rep_head $USE_REP_HEAD \
    --trainable-stem $TRAINABLE_STEM \
    --mode $MODE \
    --tag $TAG \
    --weights $WEIGHTS \
    --dataset $DATASET \
    --domain $DOMAIN \
    --data_dir $DATA_DIR \
    --device $DEVICE \
    --save_cams false \
    --save_masks false \
    --save_pseudos true \
    --threshold $INF_T \
    --crf_t $CRF_T \
    --crf_gt_prob $CRF_GT
}

make_pseudo_masks() {
  CUDA_VISIBLE_DEVICES="" \
  $PY scripts/cam/make_pseudo_masks.py \
    --experiment_name $TAG \
    --dataset $DATASET \
    --domain $DOMAIN \
    --data_dir "$DATA_DIR" \
    --pred_dir $PRED_DIR \
    --sal_dir "$SAL_DIR" \
    --output_dir "$OUTPUT_DIR" \
    --crf_t $CRF_T \
    --crf_gt_prob $CRF_GT \
    --mode $EVAL_MODE \
    --num_workers $WORKERS_INFER;
}

evaluate_pseudo_masks() {
  # This method should be used to evaluate the segmentation proposals generated by
  # `inference` or `make_pseudo_masks` methods.
  #
  # The evaluation will carry the wandb tags `t:$INF_T` and `crf:$CRF_T-$CRF_GT`,
  # referencing the DenseCRF's parameters used to generate the segmentation proposals.
  # DenseCRF will not be re-run during `evaluation` (crf_t=0).
  #
  WANDB_TAGS="$DATASET,$ARCH,u2pl,aug:$AUGMENT,lr:$LR,wd:$WD,ls:$LABELSMOOTHING,b:$BATCH,ac:$ACCUMULATE_STEPS,c2s:$C2S_MODE,warmup:$WARMUP_EPOCHS,s:$SAMPLER,rank:$CONTRA_LOW_RANK-$CONTRA_HIGH_RANK,domain:$DOMAIN,crf:$CRF_T-$CRF_GT,t:$INF_T" \
  CUDA_VISIBLE_DEVICES="" \
  $PY scripts/evaluate.py \
    --experiment_name $TAG \
    --pred_dir $PRED_DIR \
    --dataset $DATASET \
    --domain $DOMAIN \
    --data_dir $DATA_DIR \
    --min_th $MIN_TH \
    --max_th $MAX_TH \
    --mode $EVAL_MODE \
    --ignore_bg_cam $IGNORE_BG_CAM \
    --num_workers $WORKERS_INFER;
}

# region Pascal VOC 2012
#
# MAX_STEPS=46  # ceil(1464 (voc12 train samples) / 16) = 92 steps.
# ARCHITECTURE=resnest101
# ARCH=rs101
# RESTORE=experiments/models/puzzle/rs101p.pth
# REST=rs101p
# ARCHITECTURE=resnest269
# ARCH=rs269
# RESTORE=experiments/models/pnoc/voc12-rs269-pnoc-b16-lr0.1-ls@rs269-rals-r4.pth
# REST=rs269pnoc
# endregion

# region MS COCO 2014
MAX_STEPS=256   # ceil(10% of (82783 (coco14 train samples) / 32)).
CONTRA_LOW_RANK=3
CONTRA_HIGH_RANK=6  # 20
C2S_FG=0.35

ARCHITECTURE=resnest269
ARCH=rs269
RESTORE=experiments/models/pnoc/coco14-rs269-pnoc-b16-a2-lr0.05-ls0-ow0.0-1.0-1.0-c0.2-is1@rs269ra-r1.pth
REST=rs269pnoc
# ARCHITECTURE=resnest101
# ARCH=rs101
# RESTORE=experiments/models/vanilla/coco14-rs101-lr0.05-r1.pth
# REST=rs101cam
# RESTORE=experiments/models/pnoc/coco14-rs101-pnoc-b32-lr0.05@rs101-r1.pth
# REST=rs101pnoc
# endregion

EID=r1  # Experiment ID

TAG=u2pl/$DATASET-$IMAGE_SIZE-${ARCH}-lr${LR}-m$MOMENTUM-b${BATCH}-$AUGMENT-$SAMPLER-bg${C2S_BG}-fg${C2S_FG}-u$W_U-c$W_CONTRA-rank$CONTRA_LOW_RANK-$CONTRA_HIGH_RANK-hemfl@$REST-$EID
train_u2pl

WEIGHTS=experiments/models/$TAG-best.pth
PRED_ROOT=experiments/predictions/$TAG

INF_T=0.4

# DOMAIN=$DOMAIN_TRAIN inference
# DOMAIN=$DOMAIN_VALID     inference
# DOMAIN=$DOMAIN_VALID_SEG inference

# region Evaluation

# IGNORE_BG_CAM=true
# EVAL_MODE=png  ## MS COCO 2014

## Evaluation +dCRF
# PRED_DIR=$PRED_ROOT@val/pseudos-t$INF_T-c10
# DOMAIN=$DOMAIN_VALID_SEG TAG=$TAG@val evaluate_pseudo_masks

## Evaluation +dCRF +SAM
# PRED_DIR=$PRED_ROOT@val/pseudos-t$INF_T-c10/pseudos-t$INF_T-c10__max_iou_imp2
# DOMAIN=$DOMAIN_VALID_SEG TAG=$TAG@val evaluate_pseudo_masks

# endregion

# region Pseudo segmentation masks

# PRED_DIR=$PRED_ROOT@train/cams SAL_DIR=experiments/predictions/$TAG_SAL OUTPUT_DIR=$PRED_ROOT@train/pseudos-t$INF_T-c$CRF_T DOMAIN=$DOMAIN_TRAIN make_pseudo_masks
# PRED_DIR=$PRED_ROOT@val/cams SAL_DIR=experiments/predictions/$TAG_SAL OUTPUT_DIR=$PRED_ROOT@tval/pseudos-t$INF_T-c$CRF_T DOMAIN=$DOMAIN_VALID_SEG make_pseudo_masks

# endregion
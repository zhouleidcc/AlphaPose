#!/bin/bash

TEMP=`getopt -o gvliocm:fcds --long gpu:,video:,list:,indir:,outdir:,format:,mode,vis,seperate-json,cmujsonformat -n 'wrong args...' -- "$@"`

if [ $? != 0 ] ; then 
    echo "Terminating..." 
    exit 1
fi

eval set -- "${TEMP}"

GPU_ID=0

INPUT_PATH=""
OUTPUT_PATH=""
VIDEO_FILE=""
LIST_FILE=""

WORK_PATH=$(dirname $(readlink -f $0))
MODE=""
VIS=false
SEP=false 
FORMAT="default"

while true ; do
        case "$1" in
                -g|--gpu) GPU_ID="$2" ; shift 2;;
                -v|--video) VIDEO_FILE=${WORK_PATH}/$2 ; shift 2;;
                -l|--list) LIST_FILE=${WORK_PATH}/$2 ; shift 2;;
                -i|--indir) INPUT_PATH=${WORK_PATH}/$2 ; shift 2;;
                -o|--outdir) OUTPUT_PATH=${WORK_PATH}/$2 ; shift 2;;
                -f|--mode) MODE=$2 ; shift ;;
                -d|--vis) VIS=true ; shift ;;
                -s|--seperate-json) SEP=true; shift ;;
                -m|--format) FORMAT=$2 ; shift 2;;
                --) shift ; break ;;
                *) echo "Internal error!" ; exit 1 ;;
        esac
done

echo "convert video to images..."

if [ -n $VIDEO_FILE ]; then
    INPUT_PATH=${WORK_PATH}/video-tmp
    if ! [ -e $INPUT_PATH ]; then
        mkdir $INPUT_PATH
    fi
    ffmpeg -hide_banner -nostats -loglevel 0 -i ${VIDEO_FILE} -r 10 -f image2 ${INPUT_PATH}"/%05d.jpg"
fi

# echo $INPUT_PATH
# echo $OUTPUT_PATH
# echo $LIST_FILE
# echo $VIDEO_FILE
echo 'generating bbox from Faster RCNN...'

cd ${WORK_PATH}"/human-detection/tools"
CUDA_VISIBLE_DEVICES=${GPU_ID} python demo-alpha-pose.py --inputlist=${LIST_FILE} --inputpath=${INPUT_PATH} --outputpath=${OUTPUT_PATH} --mode=${MODE} --video=${VIDEO_FILE}

# echo $INPUT_PATH
# echo $OUTPUT_PATH
# echo $LIST_FILE
# echo $VIDEO_FILE

echo 'pose estimation with RMPE...'

cd ${WORK_PATH}"/predict"
if $MODE == "accurate" ; then
    CUDA_VISIBLE_DEVICES=${GPU_ID} th main-alpha-pose-4crop.lua valid ${INPUT_PATH} ${OUTPUT_PATH}
else
    CUDA_VISIBLE_DEVICES=${GPU_ID} th main-alpha-pose.lua valid ${INPUT_PATH} ${OUTPUT_PATH}
fi

cd ${WORK_PATH}"/predict/json"
python parametric-pose-nms.py --outputpath ${OUTPUT_PATH} --seperate-json ${SEP} --jsonformat ${FORMAT}


if $VIS; then
    echo 'visualization...'
    if ! [ -e ${OUTPUT_PATH}"/RENDER" ]; then
        mkdir ${OUTPUT_PATH}"/RENDER"
    fi
    python json-video.py --outputpath ${OUTPUT_PATH} --inputpath ${INPUT_PATH}
    if [ -n $VIDEO_FILE ]; then
        echo 'rendering video...'
        ffmpeg -f image2 -r 10 -i ${OUTPUT_PATH}"/RENDER/%05d.png" ${OUTPUT_PATH}"/result_MS.mp4"
    fi
fi

# delete generated video frames
cd ${WORK_PATH}
if [ -n $VIDEO_FILE ]; then
    INPUT_PATH=${WORK_PATH}/video-tmp
    rm -rf $INPUT_PATH
fi
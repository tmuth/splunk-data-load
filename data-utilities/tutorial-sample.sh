#!/bin/bash
RELATIVE_PATH=tutorialdata
OUTPUT_PATH=tutorial_sample

rm -rf ${OUTPUT_PATH}
mkdir ${OUTPUT_PATH}

function sample_data {
  #remove the first part of the path
  SUBDIR=`echo ${1} | cut -d'/' -f3`
  echo $SUBDIR
  mkdir -p ${OUTPUT_PATH}/${SUBDIR}
  TARGET_FILE=`echo ${1} | cut -d'/' -f3-`
  TARGET_FILE=${OUTPUT_PATH}/$TARGET_FILE
  echo $TARGET_FILE

  # Sample a portion of the file
  awk -v SOURCE="$1" -v TARGET="$TARGET_FILE" -v OUTPATH="${OUTPUT_PATH}" 'BEGIN  {srand()} 
     !/^$/  { if (rand() <= .05 || FNR==1) print > TARGET}' $1

  # Replace year with current year
  sed -i '' 's|/2020|/2021|g' ${TARGET_FILE}
  gzip -9 ${TARGET_FILE}
}


for file in $(find ./${RELATIVE_PATH} -name "access.log")
do
    echo "processing $file"
    sample_data $file $file
done

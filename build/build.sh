#!/bin/sh
BUILD_NUM_FILE="build_number"
increment_version ()
{
  declare -a part=( ${1//\./ } )
  declare    new
  declare -i carry=1

  for (( CNTR=${#part[@]}-1; CNTR>=0; CNTR-=1 )); do
    len=${#part[CNTR]}
    new=$((part[CNTR]+carry))
    [ ${#new} -gt $len ] && carry=1 || carry=0
    [ $CNTR -gt 0 ] && part[CNTR]=${new: -len} || part[CNTR]=${new}
  done
  new="${part[*]}"
  echo "${new// /.}"
} 
OLD_VERSION=`cat $BUILD_NUM_FILE`

NEW_VERSION=`increment_version "$OLD_VERSION"`
echo "$NEW_VERSION"
echo "$NEW_VERSION" > $BUILD_NUM_FILE
# Replace the version number in the script
if [[ ! -z "$NEW_VERSION" ]];then
    sed -i '' -E "/VERSION=/s/=.*/=$NEW_VERSION/" ../load-splunk-data.sh
else
    exit
fi

 
# Copy local changes to props.conf etc into the repo
DATA_LOAD_APP=$SPLUNK_HOME/etc/apps/tmuth-data-load/local
REPO_APP=../SPLUNK_HOME-etc-apps/tmuth-data-load/local
cp $DATA_LOAD_APP/props.conf $REPO_APP/
cp $DATA_LOAD_APP/transforms.conf $REPO_APP/
cp $DATA_LOAD_APP/fields.conf $REPO_APP/

git tag -a $NEW_VERSION -m "new release"
git push origin $NEW_VERSION

# fix tags
# git tag -d 1.0.2 # local
# git push --delete origin 1.0.2 # remote
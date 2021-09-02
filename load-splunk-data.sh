#!/bin/bash

function show_help {
  echo "

##################################################################
This script is meant to streamline the process of getting files into Splunk.
The goal is to:
1. Delete the specified INDEX and recreate it
2. Reload the input, fields, transforms, and props configs
3. oneshot load all of the files in specified directory using the defined sourcetype and INDEX
4. Count the number of events and show the field summary

This script takes 1 argument which is a configuration file containg the details of
the data to load. sample.cfg will be generated if it doesn't already exist.
##################################################################

"
}

# URL escape codes used to pass special characters. DO NOT CHANGE!
dqt="%22"
pct="%25"

function gen_sample_cfg {
  echo "
SPLUNK_HOST=localhost:8089
SPLUNK_USERNAME=admin
SPLUNK_PASS=welcome1
INDEX=sample_index
SOURCETYPE=sample_sourcetype
DIRECTORY=.
#DIRECTORY=/Volumes/GoogleDrive/My\ Drive/Projects/splunking-json/Docker/data/fio
# Either set EXTENSION to something like json to load a number of files or set FILE_NAME to a 
# specific file name to load a single file. Don't set both. Leave the unused variable empty
# with no spaces.
EXTENSION=
FILE_NAME=test.json
APP_NAME=tmuth-data-load
REPORT_FIELDS=* # first_name,ip_address,last_name
HOST_SEGMENT= # Space by default. Set to a number of the segement of filename for host if needed.
DEBUG_TIMESTAMP=F # T or F
DEBUG=T # T or F" > $CFG_FILE
}

CFG_FILE=./sample.cfg

if [[ $# -eq 0 ]] ; then
    show_help
    if [ ! -f "$CFG_FILE" ]; then
      echo "$CFG_FILE does not exist. Generating now..."
      gen_sample_cfg
    fi
    exit 0
fi

echo $1
source $1


function print_section {
  printf "\n****** ${1} ************************************************\n"
  if [[ "$1" = *"_END" ]];then
    printf "\n\n"
  fi
}

if [[ "$INDEX" = "main" ]] || [[ "$INDEX" = _* ]];then
  echo  "Index: $INDEX"
  echo "Invalid index name. Choose an index name that can be deleted and recreated."
  exit 1
fi

if [[ -z "$SPLUNK_HOME" ]];then
  echo " "
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "The SPLUNK_HOME environment variable is unset. Please configure before running this script."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo " "
  exit 1
fi
# exit 0

function splunk_search {
  #echo ${1}
  curl -s -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
    -X POST https://${SPLUNK_HOST}/services/search/jobs/ \
    -d search="${1}" \
    -d exec_mode=oneshot -d output_mode=csv -d adhoc_search_level=verbose
}

function splunk_search_columnar {
  #echo ${1}
  curl -s -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
    -X POST https://${SPLUNK_HOST}/services/search/jobs/ \
    -d search="${1}" \
    -d exec_mode=oneshot -d count=100 -d output_mode=csv | sed 's/,/ ,/g' | column -t -s, 
}

function config_reload {
  local CONFIG="${1}"
  curl --write-out "${CONFIG} reload, http-status: %{http_code}\n" --silent --output /dev/null \
    -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
    -X POST https://${SPLUNK_HOST}/services/configs/${CONFIG}/_reload
}

print_section "INDEX_CONF_BEGIN"
# delete the index
curl --write-out "delete index http-status: %{http_code}\n" --silent --output /dev/null \
  -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
  -X DELETE https://${SPLUNK_HOST}/servicesNS/nobody/${APP_NAME}/data/indexes/${INDEX}
# create the index
curl --write-out "create index http-status: %{http_code}\n" --silent --output /dev/null \
  -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
  https://${SPLUNK_HOST}/servicesNS/nobody/${APP_NAME}/data/indexes  \
    -d name=${INDEX} \
    -d datatype=event

printf "\n"
config_reload "conf-inputs"
config_reload "conf-fields"
config_reload "conf-transforms"
config_reload "conf-props"
printf "\n"
print_section "INDEX_CONF_END"


PROPS_DESIRED=( "TIME_FORMAT" "TIME_PREFIX" "MAX_TIMESTAMP_LOOKAHEAD" \
    "SHOULD_LINEMERGE" "LINE_BREAKER" "TRUNCATE" "EVENT_BREAKER_ENABLE" \
    "EVENT_BREAKER" ) 

PROPS_EXISTING=`splunk btool props list ${SOURCETYPE} --debug --app=${APP_NAME}`

function check_setting {
    check_count=`echo "$PROPS_EXISTING" | grep -c "$1"`
    #echo "$check_count"
    if [[ $check_count -eq 0 ]]; then 
        echo "Great 8 setting missing: $1"
    fi
}

printf "\n\n"
print_section "GREAT_8_BEGIN"
echo "Checking the Great 8 Settings in props.conf for sourcetype ${SOURCETYPE} in app ${APP_NAME}"
echo "$PROPS_EXISTING" | head -1

for s in ${PROPS_DESIRED[@]}; do
  check_setting "$s"
done
print_section "GREAT_8_END"
printf "\n\n"

print_section "ONESHOT_BEGIN"
for i in $(find ./${DIRECTORY} -name "*")
do
  #echo "File $i"
  CURRENT_FILE_NAME=`echo $(basename $i)`
  if ([ -z "$FILE_NAME" ] && [ "${i}" != "${i%.${EXTENSION}}" ] || [ "${CURRENT_FILE_NAME}" == "${FILE_NAME}" ]);then
    #echo "File $i $CURRENT_FILE_NAME"

    HOST_SEGMENT_COMPUTED=""
    if [ -n "$HOST_SEGMENT" ];then
      HOST_SEGMENT_COMPUTED="-host_segment ${HOST_SEGMENT}"
      echo "host segment: $HOST_SEGMENT_COMPUTED"
    fi

    ${SPLUNK_HOME}/bin/./splunk add oneshot -source "$i" -index ${INDEX} -sourcetype ${SOURCETYPE} ${HOST_SEGMENT_COMPUTED} -auth "${SPLUNK_USERNAME}:${SPLUNK_PASS} ";
    if [ "${DEBUG}" == "T" ];then
      echo "DEBUG waiting a few seconds so errors will be logged"
      sleep 3
      printf "\n\nErrors:\n"
      splunk_search "search index=_* OR index=* log_level=ERROR sourcetype=splunkd earliest=-1m 
        | where LIKE(data_source,${dqt}${pct}${i}${dqt}) 
        | eval time=strftime(_time, ${dqt}${pct}I:${pct}M:${pct}S:${pct}p${dqt})
        | table time,event_message" | sed 's/\"//g'| sed 's/,/ ,/g' | column -c 2 -t -s,
      printf "\n\n"
    fi
  fi
done
print_section "ONESHOT_END"


if [ "${DEBUG}" == "T" ];then
  print_section "BTOOL_BEGIN"
  echo "btool check for errors in sourcetype:"
  ${SPLUNK_HOME}/bin/./splunk btool check | grep ${SOURCETYPE}
  printf "\n\n"
  echo "btool debug of props.conf for sourcetype ${SOURCETYPE}:"
  ${SPLUNK_HOME}/bin/./splunk btool props list ${SOURCETYPE} --debug
  print_section "BTOOL_END"
fi 

echo "Waiting a few seconds so some of the files will be indexed..."
sleep 3

print_section "EVENT_SUMMARY_BEGIN"
printf "\n\nEvent Count:"
splunk_search "search index=${INDEX} sourcetype=${SOURCETYPE} | stats count"
printf "\n\nField Summary:\n"
splunk_search "search index=${INDEX} sourcetype=${SOURCETYPE} | fieldsummary | fields field,count" \
  | sed 's/,/ ,/g' | column -t -s,
print_section "EVENT_SUMMARY_END"

if [ "${DEBUG_TIMESTAMP}" == "T" ];then
  print_section "DEBUG_TIMESTAMP_BEGIN"

  splunk_search "search index=_internal sourcetype=splunkd (component=DateParser OR component=DateParserVerbose) earliest=-2m | transaction component _time log_level | sort _time | table _time,component,log_level,event_message "
  #index=_internal sourcetype=splunkd DateParserVerbose

  printf "\n\n_time vs _raw:\n"
  splunk_search "search index=${INDEX} sourcetype=${SOURCETYPE} earliest=1 | sort - _time | head 2 | table _time,_raw" \
  | sed 's/,/ ,/g' | column -t -s, 
  print_section "DEBUG_TIMESTAMP_END"
fi

print_section "EVENT_SEARCH_BEGIN"
echo "search index=${INDEX} sourcetype=${SOURCETYPE} earliest=-5y | sort - _time | head 20 "
splunk_search "search index=${INDEX} sourcetype=${SOURCETYPE} | sort - _time | head 20 | fields - _raw,index,timestamp,eventtype,punct,splunk_server,splunk_server_group,_bkt,_cd,tag,_sourcetype,_si,_indextime,source,_eventtype_color,linecount,${dqt}tag::eventtype${dqt},date,date_hour,date_mday,date_minute,date_month,date_second,date_wday,date_year,date_zone,_kv,_serial | fields ${REPORT_FIELDS} | table *" \
  | sed 's/,/ ,/g' | column -t -s,
print_section "EVENT_SEARCH_END"
printf "\n\n"


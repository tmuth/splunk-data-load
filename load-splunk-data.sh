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
HOST_SEGMENT= # Space by default. Set to a number of the segement of filename for host if needed." > $CFG_FILE
}

CFG_FILE=./sample.cfg

SETTINGS_FILE=./settings.txt

function gen_settings {
  echo "
# The following are global settings used to change how load-splunk-data.sh runs
#
DEBUG_TIMESTAMP=F # T or F
DEBUG=T # T or F 
SHOW_GREAT_8=T # T or F
SHOW_WALKLEX=F # T or F
SHOW_EVENT_SUMMARY=T # T or F
SHOW_INDEX_CONF=T # T or F " > $SETTINGS_FILE
}

if [[ $# -eq 0 ]] ; then
    show_help
    if [ ! -f "$CFG_FILE" ]; then
      echo "$CFG_FILE does not exist. Generating now..."
      gen_sample_cfg
    fi

    if [ ! -f "$SETTINGS_FILE" ]; then
      echo "$SETTINGS_FILE does not exist. Generating now..."
      gen_settings
    fi
    exit 0
fi

echo $1
source $1

source $SETTINGS_FILE


if [ ! -f "$SETTINGS_FILE" ]; then
  echo "$SETTINGS_FILE does not exist. Generating now..."
  gen_settings
  exit 0
fi

function should_show_section {
  #echo ${!1}
  if [ "${!1}" = "T" ] 
   then
    true
  else
    false
  fi
}



function print_section {
  #printf "\n****** ${1} ************************************************\n"
  printf "\n****** %-.100s \n" "${1} ********************************************************************************************************************************************************" 
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

function splunk_search_polling {
  SEARCH_LEVEL=${2:-verbose} 
  RESULTS=`curl -s -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
    -X POST https://${SPLUNK_HOST}/services/search/jobs \
    -d search="${1}" \
    -d adhoc_search_level=${SEARCH_LEVEL}`

    #echo "$RESULTS"
    SID=`echo $RESULTS | sed -e 's,.*<sid>\([^<]*\)<\/sid>.*,\1,g' ` 
    echo "SID: $SID"

    SEARCH_STATUS=""
    counter=10
    while [ $counter -gt 0 ]
    do
        OUTPUT=`curl -s -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
            -X GET https://${SPLUNK_HOST}/services/search/jobs/${SID}  `
        #echo "$OUTPUT"
        STATUS=`echo $OUTPUT | sed -e 's,.*<s:key name=\"dispatchState\">\([^<]*\)<\/s\:key>.*,\1,g' `
        #echo "$STATUS"
        if [[ "$STATUS" = "DONE" ]]; then
            SEARCH_STATUS="DONE"
            #echo "Leaving status loop"
            break 1
        fi
        counter=$(( $counter - 1 ))
        sleep 1
    done

    if [[ "$SEARCH_STATUS" = "DONE" ]]; then
        #echo "Getting Search Results"
        SEARCH_RESULTS=`curl -s -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
            -X GET https://${SPLUNK_HOST}/services/search/jobs/${SID}/results \
            -d output_mode=csv `
        echo "$SEARCH_RESULTS" | sed 's/,/ ,/g' | column -t -s, 
    fi
}

function config_reload {
  local CONFIG="${1}"

  curl_opts=( --silent --output /dev/null -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS})
  
  if should_show_section "SHOW_INDEX_CONF"; then
    curl_opts+=( --write-out "${CONFIG} reload, http-status: %{http_code}\n" )
  fi

  curl "${curl_opts[@]}"  -X POST https://${SPLUNK_HOST}/services/configs/${CONFIG}/_reload
}

should_show_section "SHOW_INDEX_CONF"  && print_section "INDEX_CONF_BEGIN"

curl_opts=( --silent --output /dev/null -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS})
should_show_section "SHOW_INDEX_CONF"  && curl_opts+=( --write-out "delete index http-status: %{http_code}\n" )

# delete the index
curl "${curl_opts[@]}" \
  -X DELETE https://${SPLUNK_HOST}/servicesNS/nobody/${APP_NAME}/data/indexes/${INDEX}
# create the index
if should_show_section "SHOW_INDEX_CONF"; then
  curl_opts+=( --write-out "create index http-status: %{http_code}\n" )
fi
curl  "${curl_opts[@]}" \
  https://${SPLUNK_HOST}/servicesNS/nobody/${APP_NAME}/data/indexes  \
    -d name=${INDEX} \
    -d datatype=event

#printf "\n"
config_reload "conf-inputs"
config_reload "conf-fields"
config_reload "conf-transforms"
config_reload "conf-props"
printf "\n"
should_show_section "SHOW_INDEX_CONF"  && print_section "INDEX_CONF_END"


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

if should_show_section "SHOW_GREAT_8"; then
  printf "\n\n"
  print_section "GREAT_8_BEGIN"
  echo "Checking the Great 8 Settings in props.conf for sourcetype ${SOURCETYPE} in app ${APP_NAME}"
  echo "$PROPS_EXISTING" | head -1

  for s in ${PROPS_DESIRED[@]}; do
    check_setting "$s"
  done
  print_section "GREAT_8_END"
  printf "\n\n"
fi

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

    ${SPLUNK_HOME}/bin/./splunk add oneshot -source "$i" -index ${INDEX} -sourcetype ${SOURCETYPE} ${HOST_SEGMENT_COMPUTED} -auth "${SPLUNK_USERNAME}:${SPLUNK_PASS}";
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

if should_show_section "SHOW_EVENT_SUMMARY"; then
  print_section "EVENT_SUMMARY_BEGIN"
  printf "\n\nEvent Count:"
  splunk_search "search index=${INDEX} sourcetype=${SOURCETYPE} | stats count"
  printf "\n\nField Summary:\n"
  splunk_search "search index=${INDEX} sourcetype=${SOURCETYPE} | fieldsummary | fields field,count" \
    | sed 's/,/ ,/g' | column -t -s,
  print_section "EVENT_SUMMARY_END"
fi 

if should_show_section "SHOW_WALKLEX"; then
  print_section "WALKLEX_BEGIN"
  echo "Rolling hot buckets to warm for index ${INDEX}"
  OUTPUT=`${SPLUNK_HOME}/bin/./splunk _internal call /data/indexes/${INDEX}/roll-hot-buckets -auth "${SPLUNK_USERNAME}:${SPLUNK_PASS}" | grep HTTP`
  echo "${OUTPUT}"
  printf "\n"


  SEARCH_STRING=" |  walklex index=${dqt}${INDEX}${dqt} type=field | search NOT field=${dqt} *${dqt}  "
  SEARCH_STRING+="| where  NOT LIKE(field,${dqt}date_${pct}${dqt}) "
  SEARCH_STRING+="| search NOT field IN (${dqt}source${dqt},${dqt}sourcetype${dqt},${dqt}punct${dqt},${dqt}linecount${dqt},${dqt}timeendpos${dqt},${dqt}timestartpos${dqt},${dqt}_indextime${dqt},${dqt}snc_io_parser${dqt}) "
  SEARCH_STRING+="| stats sum(distinct_values) by field"
  #echo "$SEARCH_STRING"
  splunk_search_polling "${SEARCH_STRING}"
  print_section "WALKLEX_END"
fi


if [ "${DEBUG_TIMESTAMP}" == "T" ];then
  print_section "DEBUG_TIMESTAMP_BEGIN"

  splunk_search_polling "search index=_internal sourcetype=splunkd (component=DateParser OR component=DateParserVerbose) earliest=-2m | transaction component _time log_level | sort _time | table _time,component,log_level,event_message "
  #index=_internal sourcetype=splunkd DateParserVerbose

  printf "\n\n_time vs _raw:\n"
  splunk_search_polling "search index=${INDEX} sourcetype=${SOURCETYPE} earliest=1 | sort - _time | head 2 | table _time,_raw"
  print_section "DEBUG_TIMESTAMP_END"
fi

print_section "EVENT_SEARCH_BEGIN"
echo "search index=${INDEX} sourcetype=${SOURCETYPE} earliest=-5y | sort - _time | head 20 "
splunk_search_polling "search index=${INDEX} sourcetype=${SOURCETYPE} | sort - _time | head 20 | fields - _raw,index,timestamp,eventtype,punct,splunk_server,splunk_server_group,_bkt,_cd,tag,_sourcetype,_si,_indextime,source,_eventtype_color,linecount,${dqt}tag::eventtype${dqt},date,date_hour,date_mday,date_minute,date_month,date_second,date_wday,date_year,date_zone,_kv,_serial | fields ${REPORT_FIELDS} | table *" 
print_section "EVENT_SEARCH_END"
printf "\n\n"


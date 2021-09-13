#!/bin/bash

VERSION=1.0.1

function show_help {
  echo "

VERSION: ${VERSION} 

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
dqt="%22" # double quote
pct="%25" # percent sign
dol="%24" # dollar sign
slb="%5C" # backslash

function gen_sample_cfg {
  echo "
SPLUNK_HOST=localhost:8089
AUTH_TOKEN=# Token authentication is the preferred method over username/password and is documented here:
# https://docs.splunk.com/Documentation/Splunk/latest/Security/EnableTokenAuth
SPLUNK_USERNAME=admin
SPLUNK_PASS=welcome1
INDEX=sample_index
INDEX_TYPE=event
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
DEBUG_TIMESTAMP=F # T or F    : Searches _internl component=DateParser OR component=DateParserVerbose for timestamp errors
DEBUG=T # T or F              : Searches log_level=ERROR sourcetype=splunkd after each oneshot filtering on your sourcetype
SHOW_BTOOL=F # F or F         : Shows btool 'splunk btool check' and 'splunk btool props list ${SOURCETYPE} --debug'
SHOW_GREAT_8=T # T or F       : Checks props.conf for the 'Great 8' or 'gr8' settings
SHOW_WALKLEX=F # T or F       : Rolls hot-buckets to warm, then runs walklex to show indexed-fields
SHOW_EVENT_SUMMARY=T # T or F : Searches '...| stats count' and '| fieldsummary ' 
SHOW_INDEX_CONF=T # T or F    : Displays status of index delete/create and reload of .conf files "> $SETTINGS_FILE
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


CLI_AUTH_OPTION=()
AUTH_OPTION=()
if [ ! -z "$AUTH_TOKEN" ]; then
    CLI_AUTH_OPTION+=( -token ${AUTH_TOKEN} )
    AUTH_OPTION+=( -H "Authorization: Bearer ${AUTH_TOKEN}" )
    #echo "Using Token Auth"
else
    CLI_AUTH_OPTION+=( -auth "${SPLUNK_USERNAME}:${SPLUNK_PASS}" )
    AUTH_OPTION+=( -u ${SPLUNK_USERNAME}:${SPLUNK_PASS} )
    #echo "Using User:Pass Auth"
fi


function splunk_search {
  #echo ${1}
  curl -s -k "${AUTH_OPTION[@]}" \
    -X POST https://${SPLUNK_HOST}/services/search/jobs/ \
    -d search="${1}" \
    -d exec_mode=oneshot -d output_mode=csv -d adhoc_search_level=verbose
}

function splunk_search_polling {
    SEARCH_LEVEL=${2:-verbose} 
    curl_opts_common=( -s -k -d adhoc_search_level=${SEARCH_LEVEL} )
    
    curl_opts=( "${curl_opts_common[@]}"  "${AUTH_OPTION[@]}" -d search="${1}" )
    #echo ${curl_opts[@]}

    RESULTS=`curl "${curl_opts[@]}"  -X POST https://${SPLUNK_HOST}/services/search/jobs`
 
    SID=`echo $RESULTS | sed -e 's,.*<sid>\([^<]*\)<\/sid>.*,\1,g' ` 
    printf "\n"
    echo "SID: $SID"

    SEARCH_STATUS=""
    counter=30 # will check for status=DONE this many times, every ${wait_seconds}
    wait_seconds=1
    while [ $counter -gt 0 ]
    do
        curl_opts=( "${curl_opts_common[@]}"  "${AUTH_OPTION[@]}"  )
        OUTPUT=`curl "${curl_opts[@]}" -X POST https://${SPLUNK_HOST}/services/search/jobs/${SID}`
        #echo "$OUTPUT"
        STATUS=`echo $OUTPUT | sed -e 's,.*<s:key name=\"dispatchState\">\([^<]*\)<\/s\:key>.*,\1,g' `
        #echo "$STATUS"
        if [[ "$STATUS" = "DONE" ]]; then
            SEARCH_STATUS="DONE"
            #echo "Leaving status loop"
            break 1
        fi
        counter=$(( $counter - 1 ))
        sleep ${wait_seconds}
    done

    if [[ "$SEARCH_STATUS" = "DONE" ]]; then
        curl_opts=( "${curl_opts_common[@]}"  "${AUTH_OPTION[@]}" -d output_mode=csv  )
        SEARCH_RESULTS=`curl "${curl_opts[@]}" -X GET https://${SPLUNK_HOST}/services/search/jobs/${SID}/results`
        echo "$SEARCH_RESULTS" | sed 's/,/ ,/g' | column -t -s, \
        | awk 'NR == 1 {print $0;print $0}; NR > 1 {print $0}' \
        | sed '2 s/[^[:space:]]/-/g'
    fi
}

function config_reload {
  local CONFIG="${1}"
  curl_opts=( --silent --output /dev/null -k "${AUTH_OPTION[@]}" )
  
  if should_show_section "SHOW_INDEX_CONF"; then
    curl_opts+=( --write-out "${CONFIG} reload, http-status: %{http_code}\n" )
  fi

  curl "${curl_opts[@]}"  -X POST https://${SPLUNK_HOST}/servicesNS/-/-/admin/${CONFIG}/_reload
}

should_show_section "SHOW_INDEX_CONF"  && print_section "INDEX_CONF_BEGIN"

curl_opts=( --silent --output /dev/null -k "${AUTH_OPTION[@]}")
should_show_section "SHOW_INDEX_CONF"  && curl_opts+=( --write-out "delete index http-status: %{http_code}\n" )

# delete the index
curl "${curl_opts[@]}" \
  -X DELETE https://${SPLUNK_HOST}/servicesNS/nobody/${APP_NAME}/data/indexes/${INDEX}
# create the index
if should_show_section "SHOW_INDEX_CONF"; then
  curl_opts+=( --write-out "create index http-status: %{http_code}\n" )
fi

INDEX_DATA_TYPE=${INDEX_TYPE:-event} 
curl  "${curl_opts[@]}" \
  https://${SPLUNK_HOST}/servicesNS/nobody/${APP_NAME}/data/indexes  \
    -d name=${INDEX} \
    -d datatype=${INDEX_DATA_TYPE}

#printf "\n"
config_reload "conf-inputs"
config_reload "conf-fields"
config_reload "conf-transforms"
config_reload "transforms-reload"
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

    #echo ${CLI_AUTH_OPTION[@]}
    ${SPLUNK_HOME}/bin/./splunk add oneshot -source "$i" -index ${INDEX} -sourcetype ${SOURCETYPE} ${HOST_SEGMENT_COMPUTED} ${CLI_AUTH_OPTION[@]};

    if [ "${DEBUG}" == "T" ];then
      echo "DEBUG waiting a few seconds so errors will be logged"
      sleep 3
      printf "\n\nErrors:\n"
      splunk_search_polling "search index=_* OR index=* log_level=ERROR sourcetype=splunkd earliest=-1m 
        | where LIKE(data_source,${dqt}${pct}${i}${dqt}) 
        | eval time=strftime(_time, ${dqt}${pct}I:${pct}M:${pct}S:${pct}p${dqt})
        | table time,event_message" 
      printf "\n\n"
    fi
  fi
done
print_section "ONESHOT_END"


if [ "${SHOW_BTOOL}" == "T" ];then
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
  if [ "${INDEX_DATA_TYPE}" == "event" ];then
    print_section "EVENT_SUMMARY_BEGIN"
    printf "\n\nEvent Count:"
    splunk_search_polling "search index=${INDEX} sourcetype=${SOURCETYPE} | stats count"
    printf "\n\nField Summary:\n"
    splunk_search_polling "search index=${INDEX} sourcetype=${SOURCETYPE} | fieldsummary | fields field,count" 
    print_section "EVENT_SUMMARY_END"
  fi
fi 

if should_show_section "SHOW_WALKLEX"; then
  if [ "${INDEX_DATA_TYPE}" == "event" ];then
    print_section "WALKLEX_BEGIN"
    echo "Rolling hot buckets to warm for index ${INDEX}"
    OUTPUT=`${SPLUNK_HOME}/bin/./splunk _internal call /data/indexes/${INDEX}/roll-hot-buckets ${CLI_AUTH_OPTION[@]} | grep HTTP`
    echo "${OUTPUT}"
    printf "\n"


    SEARCH_STRING=" |  walklex index=${dqt}${INDEX}${dqt} type=field | search NOT field=${dqt} *${dqt}  "
    SEARCH_STRING+="| where  NOT LIKE(field,${dqt}date_${pct}${dqt}) "
    SEARCH_STRING+="| search NOT field IN (${dqt}source${dqt},${dqt}sourcetype${dqt},${dqt}punct${dqt},${dqt}linecount${dqt},${dqt}timeendpos${dqt},${dqt}timestartpos${dqt},${dqt}_indextime${dqt},${dqt}snc_io_parser${dqt}) "
    SEARCH_STRING+="| rename field as indexed_field "
    SEARCH_STRING+="| stats sum(distinct_values) by indexed_field"
    #echo "$SEARCH_STRING"
    splunk_search_polling "${SEARCH_STRING}"
    print_section "WALKLEX_END"
  fi
fi


if [ "${DEBUG_TIMESTAMP}" == "T" ];then
  print_section "DEBUG_TIMESTAMP_BEGIN"

  splunk_search_polling "search index=_internal sourcetype=splunkd (component=DateParser OR component=DateParserVerbose) earliest=-2m | transaction component _time log_level | sort _time | table _time,component,log_level,event_message "
  #index=_internal sourcetype=splunkd DateParserVerbose

  printf "\n\n_time vs _raw:\n"
  splunk_search_polling "search index=${INDEX} sourcetype=${SOURCETYPE} earliest=1 | sort - _time | head 2 | table _time,_raw"
  print_section "DEBUG_TIMESTAMP_END"
fi

if [ "${INDEX_DATA_TYPE}" == "event" ];then
  print_section "EVENT_SEARCH_BEGIN"
  echo "search index=${INDEX} sourcetype=${SOURCETYPE} earliest=-5y | sort - _time | head 20 "
  splunk_search_polling "search index=${INDEX} sourcetype=${SOURCETYPE} | sort - _time | head 20 | fields - _raw,index,timestamp,eventtype,punct,splunk_server,splunk_server_group,_bkt,_cd,tag,_sourcetype,_si,_indextime,source,_eventtype_color,linecount,${dqt}tag::eventtype${dqt},date,date_hour,date_mday,date_minute,date_month,date_second,date_wday,date_year,date_zone,_kv,_serial | fields ${REPORT_FIELDS} | table *" 
  print_section "EVENT_SEARCH_END"
  printf "\n\n"
else
  print_section "METRIC_SUMMARY_BEGIN"
  printf "\n\nMetric Names:\n"
  SEARCH_STRING=" | mcatalog values(metric_name) as metric_name  WHERE index=${INDEX} | mvexpand metric_name | table metric_name "
  echo "${SEARCH_STRING}"
  splunk_search_polling "${SEARCH_STRING}"

  printf "\n\nMetric Dimensions:\n"
  SEARCH_STRING=" | mcatalog values(_dims) AS dimensions  WHERE index=${INDEX} | mvexpand dimensions | table dimensions "
  echo "${SEARCH_STRING}"
  splunk_search_polling "${SEARCH_STRING}"

  printf "\n\nMetric Value Summary by Metric Name:\n"

  SEARCH_STRING=" | mcatalog values(metric_name) as metric_name WHERE index=drive_metrics "
  SEARCH_STRING+="| mvexpand metric_name "
  SEARCH_STRING+="| map search=${dqt} | mstats avg(_value) as avg_value prestats=false WHERE metric_name=${slb}${dqt}${dol}metric_name${dol}${slb}${dqt} AND index=${slb}${dqt}drive_metrics${slb}${dqt} by metric_name span=1m ${dqt} "
  SEARCH_STRING+="| stats avg(avg_value) as avg_value,min(_time) as min_time,max(_time) as max_time by metric_name "
  SEARCH_STRING+="| eval min_time=strftime(min_time,${dqt}${pct}m/${pct}d/${pct}y ${pct}H:${pct}M${dqt}),max_time=strftime(max_time,${dqt}${pct}m/${pct}d/${pct}y ${pct}H:${pct}M${dqt}),avg_value=round(avg_value,1) "
  SEARCH_STRING+="| table metric_name,avg_value,min_time,max_time "
  echo "${SEARCH_STRING}"
  splunk_search_polling "${SEARCH_STRING}"

  print_section "METRIC_SUMMARY_END"
  printf "\n\n"
fi

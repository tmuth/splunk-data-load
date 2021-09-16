#!/bin/bash

SPLUNK_HOST=localhost:8089
SPLUNK_USERNAME=admin
SPLUNK_PASS=welcome1

AUTH_TOKEN="eyJraWQiOiJzcGx1bmsuc2VjcmV0IiwiYWxnIjoiSFM1MTIiLCJ2ZXIiOiJ2MiIsInR0eXAiOiJzdGF0aWMifQ.eyJpc3MiOiJhZG1pbiBmcm9tIHRtdXRoLW1icC1lNDFlOSIsInN1YiI6ImFkbWluIiwiYXVkIjoiUkVTVCBDYWxscyIsImlkcCI6IlNwbHVuayIsImp0aSI6IjA1MzU4ZjYzZjFjZjVkNzdhMjcwMzg1NzM0NDFmMTZiNTgxZWIxMGY1M2RlNzYyNWE4ZThkMTBhM2Y3YzY2OTMiLCJpYXQiOjE2MzEyODYyNzYsImV4cCI6MTY5NDM1ODI3NiwibmJyIjoxNjMxMjg2Mjc2fQ.RQdjHDkozi59yfn-Dh7BhaUmTuWrIT2y5textF7G3t3FTMk5npCUC2GzORyH4PdiKZUXvNb17UGAELOe6Nvifw"



function print_section {
  #printf "\n****** ${1} ************************************************\n"
  printf "\n****** %-.80s \n" "${1} ************************************************************************************************" 
  if [[ "$1" = *"_END" ]];then
    printf "\n\n"
  fi
}

print_section "ONESHOT_BEGIN"
print_section "ONESHOT_END"


# exit 0

# URL escape codes used to pass special characters. DO NOT CHANGE!
dqt="%22"
pct="%25"

function splunk_search_polling {
    SEARCH_LEVEL=${2:-verbose} 
    curl_opts_common=( -s -k -d adhoc_search_level=${SEARCH_LEVEL} )

    AUTH_OPTION=()
    if [ ! -z "$AUTH_TOKEN" ]; then
        AUTH_OPTION+=( -H "Authorization: Bearer ${AUTH_TOKEN}" )
        #echo "Using Token Auth"
    else
        AUTH_OPTION+=( -u ${SPLUNK_USERNAME}:${SPLUNK_PASS} )
        #echo "Using User:Pass Auth"
    fi
    
    curl_opts=( "${curl_opts_common[@]}"  "${AUTH_OPTION[@]}" -d search="${1}" )
    #echo ${curl_opts[@]}

    RESULTS=`curl "${curl_opts[@]}"  -X POST https://${SPLUNK_HOST}/services/search/jobs`
 
    SID=`echo $RESULTS | sed -e 's,.*<sid>\([^<]*\)<\/sid>.*,\1,g' ` 
    printf "\n"
    echo "SID: $SID"

    SEARCH_STATUS=""
    counter=30 # will check for status=DONE this many times, every ${wait_seconds}
    wait_seconds=0.5
    while [ $counter -gt 0 ]
    do
        curl_opts=( "${curl_opts_common[@]}"  "${AUTH_OPTION[@]}"  )
        OUTPUT=`curl "${curl_opts[@]}" -X POST https://${SPLUNK_HOST}/services/search/jobs/${SID}`
        #echo "$OUTPUT"
        PROGRESS=`echo $OUTPUT | sed -e 's,.*<s:key name=\"doneProgress\">\([^<]*\)<\/s\:key>.*,\1,g' `
        STATUS=`echo $OUTPUT | sed -e 's,.*<s:key name=\"dispatchState\">\([^<]*\)<\/s\:key>.*,\1,g' `
        echo "$STATUS"
        echo "$PROGRESS"
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



function splunk_search_oneshot {
  #echo ${1}
  printf "\n\n"
  echo "splunk_search_oneshot - adhoc_search_level: ${2}"
  curl -s -k -u ${SPLUNK_USERNAME}:${SPLUNK_PASS}  \
    -X POST https://${SPLUNK_HOST}/services/search/jobs/ \
    -d search="${1}" \
    -d exec_mode=oneshot -d output_mode=csv -d adhoc_search_level=${2}
}


SEARCH_STRING="search index=_internal sourcetype=splunkd component=Metrics earliest=-5m | table _time, group, name | head 5 "

#splunk_search_polling "${SEARCH_STRING}" "verbose"
#splunk_search_polling "${SEARCH_STRING}" "fast"

#splunk_search_oneshot "${SEARCH_STRING}" "verbose"
#splunk_search_oneshot "${SEARCH_STRING}" "fast"

INDEX=main
SEARCH_STRING=" |  walklex index=${dqt}${INDEX}${dqt} type=field | search NOT field=${dqt} *${dqt} | where  NOT LIKE(field,${dqt}date_${pct}${dqt}) | stats sum(distinct_values) by field "
#SEARCH_STRING=" search | walklex index=$INDEX  earliest=1 "
#splunk_search_polling "${SEARCH_STRING}" "verbose"

splunk_search_polling "search index=main | stats count by sourcetype"


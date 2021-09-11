# splunk-data-load
A script to assist in iteratively loading data into Splunk while making modifications to config files such as inputs.conf, props.conf and transforms.conf

This script is meant to streamline the process of getting files into Splunk.
The goal is to:
1. Delete the specified INDEX and recreate it
2. Reload the input, fields, transforms, and props configs
3. oneshot load all of the files in specified directory using the defined sourcetype and INDEX
4. Count the number of events and show the field summary

This script takes 1 argument which is a configuration file containg the details of
the data to load. sample.cfg and settings.txt will be generated if they don't already exist.

## Instructions
1. Run the script with no parmeters to generate sample.cfg
2. Optionally rename sample.cfg and edit the parameters in it, such as AUTH_TOKEN. For instructions on setting up token authentication review [this doc](https://docs.splunk.com/Documentation/Splunk/latest/Security/Setupauthenticationwithtokens).
3. Run the script, passing the newly edited .cfg file as the only parameter:
```
./load-splunk-data.sh sample.cfg
```
4. Review the output. Make any desired changes to props.conf, transforms.conf, and fields.conf and re-run the script.

## What problems does this script solve?
The GUI is great for getting simple data in that only requires changes to props.conf. There are a number of scenarios that also require changes to transforms.conf and/or fields.conf such as:
- Index-time field extractions
- log2metrics conversion
- Data redaction

The process to make changes and test them usually involves multiple steps including changing files, hitting the `.../debug/refresh` URL in a browser, oneshot load from the command line, searching results in several other browser tabs. This process can be cumbersome and time consuming. This script performs all of those actions in a single call. 

## Settings
The first time the script is run without any parameters, `settings.txt` is generated if it doesn't already exist. These are global settings that control behavior and output of the script. Descriptions:
- DEBUG_TIMESTAMP=F # T or F    : Searches _internl component=DateParser OR component=DateParserVerbose for timestamp errors
- DEBUG=T # T or F              : Searches log_level=ERROR sourcetype=splunkd after each oneshot filtering on your sourcetype
- SHOW_BTOOL=F # F or F         : Shows btool 'splunk btool check' and 'splunk btool props list ${SOURCETYPE} --debug'
- SHOW_GREAT_8=T # T or F       : Checks props.conf for the 'Great 8' or 'gr8' settings
- SHOW_WALKLEX=F # T or F       : Rolls hot-buckets to warm, then runs walklex to show indexed-fields
- SHOW_EVENT_SUMMARY=T # T or F : Searches '...| stats count' and '| fieldsummary ' 
- SHOW_INDEX_CONF=T # T or F    : Displays status of index delete/create and reload of .conf files

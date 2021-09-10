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
2. Optionally rename sample.cfg and edit the parameters in it, such as AUTH_TOKEN. For instructions on setting up token authentication review this doc: https://docs.splunk.com/Documentation/Splunk/latest/Security/Setupauthenticationwithtokens
3. Run the script, passing the newly edited .cfg file as the only parameter:
```
./load-splunk-data.sh sample.cfg
```
4. Review the output. Make any desired changes to props.conf, transforms.conf, and fields.conf and re-run the script.

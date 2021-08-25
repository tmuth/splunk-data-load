# splunk-data-load
A script to assist in iteratively loading data into Splunk while making modifications to config files such as inputs.conf, props.conf and transforms.conf

This script is meant to streamline the process of getting files into Splunk.
The goal is to:
1. Delete the specified INDEX and recreate it
2. Reload the input, fields, transforms, and props configs
3. oneshot load all of the files in specified directory using the defined sourcetype and INDEX
4. Count the number of events and show the field summary

This script takes 1 argument which is a configuration file containg the details of
the data to load. sample.cfg will be generated if it doesn't already exist.

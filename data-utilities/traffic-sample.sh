#!/bin/bash

awk 'BEGIN  {srand()} 
     !/^$/  { if (rand() <= .05 || FNR==1) print > "traffic.csv"}' Traffic_Violations-API.csv

#sed -i '' 's|/2020|/2021|g' traffic.csv
gzip -9 traffic.csv

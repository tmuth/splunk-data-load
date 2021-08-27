#!/bin/bash
gsplit -l 100 --numeric-suffixes people1.json people_
mkdir peoplesplit
mv people_* peoplesplit/
cd peoplesplit
rename -v -- 's/$/.json/' *
gzip -9 *.json

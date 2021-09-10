a='dimensions
"drive_serial" '

b='"metric_name"                                     "avg_value"   "min_time"         "max_time"
"drive-metrics.drive_spin_rpm_0"                  "50.0"        "08/24/21 08:36"   "09/10/21 03:14"
"drive-metrics.file_system_drive_read_errors_0"   "49.5"        "08/24/21 08:39"   "09/10/21 03:18"
"drive-metrics.maximum_seek_time_0"               "49.8"        "08/24/21 08:41"   "09/10/21 03:19"
"drive-metrics.minimum_seek_time_0"               "49.7"        "08/24/21 08:43"   "09/10/21 03:21"
"drive-metrics.standard_deviation_seek_time_0"    "50.7"        "08/24/21 08:38"   "09/10/21 03:16"'

function test {
    echo "$1" | awk 'NR == 1 {print $0;print $0}; NR > 1 {print $0}' | sed '2 s/[^[:space:]]/-/g'
    printf "\n"
}

echo "$a"
echo "$b"

printf "\n\n"

test "$a"
test "$b"
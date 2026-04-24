#!/bin/bash

# Copyright (c) 2018 Baidu.com, Inc. All Rights Reserved
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# source shflags from current directory
mydir="${BASH_SOURCE%/*}"
if [[ ! -d "$mydir" ]]; then mydir="$PWD"; fi
. $mydir/../shflags

# define command-line flags
DEFINE_string crash_on_fatal 'true' 'Crash on fatal log' c
DEFINE_integer bthread_concurrency '18' 'Number of worker pthreads' b
DEFINE_string sync 'true' 'fsync each time' s
DEFINE_string valgrind 'false' 'Run in valgrind' v
DEFINE_integer max_segment_size '8388608' 'Max segment size' m
DEFINE_integer server_num '3' 'Number of servers' n
DEFINE_boolean clean 1 'Remove old "runtime" dir before running' l
DEFINE_integer port 8100 "Port of the first server" p

if [[ "$(uname)" == "Darwin" ]]; then
    for arg in "$@"; do
        case "$arg" in
            --crash_on_fatal=*) FLAGS_crash_on_fatal="${arg#*=}" ;;
            --bthread_concurrency=*) FLAGS_bthread_concurrency="${arg#*=}" ;;
            --sync=*) FLAGS_sync="${arg#*=}" ;;
            --valgrind=*) FLAGS_valgrind="${arg#*=}" ;;
            --max_segment_size=*) FLAGS_max_segment_size="${arg#*=}" ;;
            --server_num=*) FLAGS_server_num="${arg#*=}" ;;
            --clean) FLAGS_clean=0 ;;
            --clean=*) FLAGS_clean="${arg#*=}" ;;
            --port=*) FLAGS_port="${arg#*=}" ;;
            *) echo "Unknown option: $arg" >&2; exit 1 ;;
        esac
    done
else
    FLAGS "$@" || exit 1
    eval set -- "${FLAGS_ARGV}"
fi

# The alias for printing to stderr
alias error=">&2 echo counter: "

# hostname prefers ipv6 on Linux; macOS does not support `hostname -i`.
IP=`hostname -i 2>/dev/null | awk '{print $NF}'`
if [ -z "$IP" ]; then
    IP=`ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}'`
fi
if [ -z "$IP" ]; then
    IP="127.0.0.1"
fi

if [ "$FLAGS_valgrind" == "true" ] && [ $(which valgrind) ] ; then
    VALGRIND="valgrind --tool=memcheck --leak-check=full"
fi

raft_peers=""
for ((i=0; i<$FLAGS_server_num; ++i)); do
    raft_peers="${raft_peers}${IP}:$((${FLAGS_port}+i)):0,"
done

if [ "$FLAGS_clean" == "0" ]; then
    rm -rf runtime
fi

export TCMALLOC_SAMPLE_PARAMETER=524288

for ((i=0; i<$FLAGS_server_num; ++i)); do
    mkdir -p runtime/$i
    cp ./counter_server runtime/$i
    cd runtime/$i
    ${VALGRIND} ./counter_server \
        -bthread_concurrency=${FLAGS_bthread_concurrency}\
        -raft_max_segment_size=${FLAGS_max_segment_size} \
        -raft_sync=${FLAGS_sync} \
        -port=$((${FLAGS_port}+i)) -conf="${raft_peers}" > std.log 2>&1 &
    cd ../..
done

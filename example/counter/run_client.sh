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
DEFINE_boolean clean 1 'Remove old "runtime" dir before running' c
DEFINE_integer add_percentage 100 'Percentage of fetch_add operation' a
DEFINE_integer bthread_concurrency '8' 'Number of worker pthreads' b
DEFINE_integer server_port 8100 "Port of the first server" p
DEFINE_integer server_num '3' 'Number of servers' n
DEFINE_integer thread_num 1 'Number of sending thread' t
DEFINE_string crash_on_fatal 'true' 'Crash on fatal log' r
DEFINE_string log_each_request 'false' 'Print log for each request' l
DEFINE_string valgrind 'false' 'Run in valgrind' v
DEFINE_string use_bthread "true" "Use bthread to send request" u

if [[ "$(uname)" == "Darwin" ]]; then
    for arg in "$@"; do
        case "$arg" in
            --clean) FLAGS_clean=0 ;;
            --clean=*) FLAGS_clean="${arg#*=}" ;;
            --add_percentage=*) FLAGS_add_percentage="${arg#*=}" ;;
            --bthread_concurrency=*) FLAGS_bthread_concurrency="${arg#*=}" ;;
            --server_port=*) FLAGS_server_port="${arg#*=}" ;;
            --server_num=*) FLAGS_server_num="${arg#*=}" ;;
            --thread_num=*) FLAGS_thread_num="${arg#*=}" ;;
            --crash_on_fatal=*) FLAGS_crash_on_fatal="${arg#*=}" ;;
            --log_each_request=*) FLAGS_log_each_request="${arg#*=}" ;;
            --valgrind=*) FLAGS_valgrind="${arg#*=}" ;;
            --use_bthread=*) FLAGS_use_bthread="${arg#*=}" ;;
            *) echo "Unknown option: $arg" >&2; exit 1 ;;
        esac
    done
else
    FLAGS "$@" || exit 1
fi

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
    raft_peers="${raft_peers}${IP}:$((${FLAGS_server_port}+i)):0,"
done

export TCMALLOC_SAMPLE_PARAMETER=524288

${VALGRIND} ./counter_client \
        --add_percentage=${FLAGS_add_percentage} \
        --bthread_concurrency=${FLAGS_bthread_concurrency} \
        --conf="${raft_peers}" \
        --log_each_request=${FLAGS_log_each_request} \
        --thread_num=${FLAGS_thread_num} \
        --use_bthread=${FLAGS_use_bthread} \

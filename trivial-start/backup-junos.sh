#!/bin/bash

# Very very simple script inspired by RANCID being complicated

REPO=$HOME/backup/junos

commands=("version" "config" "chassis environment" "chassis firmware" "chassis hardware detail" "chassis routing-engine" "chassis alarms" "interfaces brief" "system boot-messages" "system core-dumps" "system license" "vlans extensive" "system commit")

while [[ $1 ]]; do
    router=$1
    shift
    [[ -d "$REPO/$router" ]] || mkdir -p "$REPO/$router"
    pushd "$REPO/$router"
    tmpfile=$(mktemp)
    for cmd in "${commands[@]}"; do
        ssh $router "show $cmd" > $tmpfile && mv $tmpfile "$cmd"
    done
    git init
    git add .
    git commit -m "$router : $(head -1 config)"
    git push
    popd
    rm -f $tmpfile
done

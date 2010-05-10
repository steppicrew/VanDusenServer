#!/bin/bash

#while (pgrep -f python || pgrep -f perl) > /dev/null
while pgrep -f python > /dev/null
do
    sleep 10
done

echo "shutting down system!"
sleep 60

ssh agency@proxy 'sh power/off.sh'

halt


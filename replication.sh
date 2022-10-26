#!/bin/bash

log=/var/log/replication.log

remote_server=my_server_to_backup.somewhere.com
remote_pools=("bpool" "rpool")

for remote_set in $(ssh root@$remote_server zfs list -H -d1 -o name "${remote_pools[@]}"); do remote_datasets+=( "$remote_set" ); done

echo "`date` starting replication.sh" >> $log 2>&1
echo "`date` sleep 10 seconds - allow server time to make snaps" >> $log 2>&1

sleep 10 # Give the other system time to make its snapshots

for sync_to_local in "${remote_datasets[@]}"; do
   [[ ! "$sync_to_local" =~ / ]] && continue
   echo "`date` starting sync of $sync_to_local " >> $log 2>&1
   /usr/local/sbin/syncoid --recvoptions="u" --sendoptions="p" --no-sync-snap --quiet \
      -c aes128-gcm@openssh.com -r root@$remote_server:"$sync_to_local" "$sync_to_local" 2>&1 | \
      ts '%a %b %e %H:%M:%S %Z %Y' >> $log 2>&1
   echo "`date` synced $sync_to_local " >> $log 2>&1
   echo "`date` checking for local snapshots not on remote server" >> $log 2>&1
   extra_snaps_array=()
   local_snaps=$(/sbin/zfs list -H -r -s name -o name -t snapshot "$sync_to_local")
   remote_snaps=$(ssh root@$remote_server zfs list -H -r -s name -o name -t s${RECVOPTS}napshot "$sync_to_local" )
   for extras in $(comm -23  <(echo "$local_snaps") <(echo "$remote_snaps")); do extra_snaps_array+=( "$extras" ); done
      if [[ -z "$remote_snaps" ]]; then
      echo "`date` Unable to retrieve remote snapshots for $sync_to_local" >> $log 2>&1
   elif [[ ${#local_snaps[@]} -lt ${#remote_snaps[@]} ]]; then
      echo "`date` $sync_to_local local snapshot count: ${#local_snaps[@]} is less than remote snapshot count: ${#remote_snaps[@]}!" >> $log 2>&1
   elif [[ ${#extra_snaps_array[@]} -eq 0 ]]; then
      echo "`date` No extra snapshots for $sync_to_local were found!" >> $log 2>&1
   else
      for extra_snap in "${extra_snaps_array[@]}"; do
         echo "`date` destroying $extra_snap" >> $log 2>&1
         /sbin/zfs destroy "$extra_snap"
      done
   fi
done



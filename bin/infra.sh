#!/usr/bin/env bash
set -e # - exit on error.

MACHINES=4
MACHINE_PREFIX='mongo-'
MACHINE_CONFIG='\
	--driver virtualbox \
	--virtualbox-cpu-count 1 \
	--virtualbox-disk-size 8192 \
	--virtualbox-memory 1024
'
CONTAINER=mongo
REPLICA_SET_NAME=rs0

# Fill machine names:
MACHINE_NAMES=()
for i in $(seq 1 $MACHINES); do
	MACHINE_NAMES[$i]=${MACHINE_PREFIX}$i
done
MACHINE=${MACHINE_NAMES[1]}

# Log function:
log () {
	type=$1
	shift
	case $type in
		error)
			echo $* >&2 
			;;

		info|warning)
			echo $*
			;;

		*)
			echo "Unknown log type '$type'."
			exit 2
			;;
	esac
}

mongo-container-id () {
    docker ps --quiet --filter=name=$CONTAINER
}

mongo-exec () {
    docker exec $CONTAINER mongo --quiet --eval "$1"
}

mongo-replica-version () {
    mongo-exec 'rs.conf().version' 2>/dev/null || echo 0
}

mongo-wait () {
	log info 'Waiting for mongo...'
	while :; do
		mongo-exec --eval "db.version()" 2>/dev/null && break || sleep 1 
	done
	log info 'Mongo started successfully!'
}

to-machine () {
	name=$1
	if [[ $(docker-machine status $name) != 'Running' ]]; then
		log error "Machine '$name' is not running."
		return 1
	fi
    eval $(docker-machine env $name)
}

case $1 in
	'machines-create')
		log info 'Creating machines...'
		for name in ${MACHINE_NAMES[@]}; do
			docker-machine status $name > /dev/null ||\
				docker-machine create $name $MACHINE_CONFIG
		done
		log info 'Created all machines.'
		;;

    'machines-start')
        log info 'Starting machines...'
        for name in ${MACHINE_NAMES[@]}; do
            if [[ $(docker-machine status $name) = 'Running' ]]; then
                continue;
            fi
            docker-machine start $name
        done
        log info 'All machines started.'
        ;;


	'mongos-stop')
	    log info 'Stopping mongos...'
	    for name in ${MACHINE_NAMES[@]}; do
	        to-machine $name || continue
	        log info "Stopping mongo on '$name'..."
	        containers=$(mongo-container-id)
	        if [[ "$containers" = '' ]]; then
	            log info 'No running containers found.'
	            continue
	        fi
	        docker stop $containers
	    done
	    ;;

	'mongos-run')
	    log info 'Running mongos...'
	    for name in ${MACHINE_NAMES[@]}; do
	        to-machine $name || continue
	        ip=$(docker-machine ip $name)
	        log info "Running mongo on '$name' ($ip)..."
	        if [[ $(mongo-container-id) != '' ]]; then
	            log info 'Already running.'
	            continue
	        fi
	        docker run \
	            --rm \
	            --detach \
                --name $CONTAINER \
                --publish 27017:27017 \
                mongo:3.2.20 \
                    --replSet $REPLICA_SET_NAME
			mongo-wait
	    done
	    ;;

	'mongos-insert-users')
		# TODO:
		to-machine $MACHINE

		DUMP_LOCAL=./data/dump.js
		DUMP_REMOTE=//dump.js

		if [[ ! -e $DUMP_LOCAL ]]; then
			log info "Creating dump $DUMP_LOCAL."
			docker run \
				--rm \
				--volume /$PWD://app \
				--workdir //app \
				--name php-cli \
				php:7.2.5-cli \
					bin/create-dump.php $DUMP_LOCAL
		fi

		log info "Sending dump to $CONTAINER $DUMP_LOCAL -> $DUMP_REMOTE"
		docker cp $DUMP_LOCAL $CONTAINER:DUMP_REMOTE
		docker exec $CONTAINER bash -c 'mongo < DUMP_REMOTE'
		;;



    'mongos-configure')
        log info 'Configuring mongos...'
        if [[ $(mongo-replica-version) = 1 ]]; then
            log info 'Already configured.'
            exit
        fi
        members=''
        id=0
	    for name in ${MACHINE_NAMES[@]}; do
	        [[ $name = $MACHINE ]] && priority=1 || priority=0.5
	        ip=$(docker-machine ip $name)
            members=$members'{"_id":'$id',"host":"'$ip':27017","priority":'$priority'},'
            id=$((id+1))
	    done

        js=$(cat <<JAVASCRIPT
rs.initiate( {
   _id : "$REPLICA_SET_NAME",
   members: [$members]
})
JAVASCRIPT
        )

        to-machine $MACHINE
        response=$(mongo-exec "$js")

        if [[ $(echo "$response" | jq .ok) != 1 ]]; then
            log warning 'Warning: '$(echo "$response" | jq -r .info) >&2
        fi

	    for name in ${MACHINE_NAMES[@]}; do
	        to-machine $name
	        log info "Waiting for $name replica."
	        while [[ $(mongo-replica-version) = 0 ]]; do
	        	sleep 1
	        done
	    done
        ;;

    'mongos-info')
        log info "Status of Mongos in replica set."
        to-machine $(docker-machine ls --filter name=$MACHINE_PREFIX --quiet | head -n1)
	    mongo-exec 'rs.status().members'
        ;;
	*)
		cat <<USAGE
Machine commands:
machines-create - create all machines.
machines-start - start all machines.
machines-stop - stop all machines.

Mongo-commands:
mongos-run - run Mongo instances.
mongos-stop - stop and remove Mongo instances.
mongos-configure - set-up Mongo replicas.
mongos-insert-users - insert users data.
mongos-info - get replica set info.
USAGE
		exit 1
		;;
esac
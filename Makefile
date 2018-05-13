# Global commands:
run: \
	machines-create \
	machines-start \
	mongos-run \
	mongos-configure \
	mongos-insert-users \
	mongos-info
stop:
	bin/infra.sh mongos-stop
rerun: stop run

# Machines:
machines-create:
	bin/infra.sh machines-create
machines-start:
	bin/infra.sh machines-start

# Mongos:
mongos-run:
	bin/infra.sh mongos-run
mongos-configure:
	bin/infra.sh mongos-configure
mongos-info:
	bin/infra.sh mongos-info
mongos-insert-users:
	bin/infra.sh mongos-insert-users
IMAGE_NAMESPACE ?= okfn-brasil
IMAGE_NAME ?= querido-diario-data-processing
IMAGE_TAG ?= latest
APACHE_TIKA_IMAGE_NAME ?=  querido-diario-apache-tika-server
APACHE_TIKA_IMAGE_TAG ?= latest
POD_NAME ?= querido-diario-data-extraction

# S3 mock
STORAGE_BUCKET ?= queridodiariobucket
STORAGE_IMAGE ?= docker.io/bitnami/minio:2021.4.6
STORAGE_CONTAINER_NAME ?= queridodiario-storage
STORAGE_ACCESS_KEY ?= minio-access-key
STORAGE_ACCESS_SECRET ?= minio-secret-key
STORAGE_PORT ?= 9000
# Database info user to run the tests
DATABASE_CONTAINER_NAME ?= queridodiario-db
POSTGRES_PASSWORD ?= queridodiario
POSTGRES_USER ?= $(POSTGRES_PASSWORD)
POSTGRES_DB ?= queridodiariodb
POSTGRES_HOST ?= localhost
POSTGRES_PORT ?= 5432
POSTGRES_IMAGE ?= docker.io/postgres:10
DATABASE_RESTORE_FILE ?= contrib/data/queridodiariodb.tar
# Elasticsearch info to run the tests
ELASTICSEARCH_PORT1 ?= 9200
ELASTICSEARCH_PORT2 ?= 9300
ELASTICSEARCH_CONTAINER_NAME ?= queridodiario-elasticsearch
APACHE_TIKA_CONTAINER_NAME ?= queridodiario-apache-tika-server

run-command=(docker  run --rm -ti --volume $(PWD):/mnt/code:rw \
	--env PYTHONPATH=/mnt/code \
	--env POSTGRES_PASSWORD=$(POSTGRES_PASSWORD) \
	--env POSTGRES_USER=$(POSTGRES_USER) \
	--env POSTGRES_DB=$(POSTGRES_DB) \
	--env POSTGRES_HOST=$(POSTGRES_HOST) \
	--env POSTGRES_PORT=$(POSTGRES_PORT) \
	$(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG) $1)

wait-for=(docker  run --rm -ti --volume $(PWD):/mnt/code:rw \
	--env PYTHONPATH=/mnt/code \
	--env POSTGRES_PASSWORD=$(POSTGRES_PASSWORD) \
	--env POSTGRES_USER=$(POSTGRES_USER) \
	--env POSTGRES_DB=$(POSTGRES_DB) \
	--env POSTGRES_HOST=$(POSTGRES_HOST) \
	--env POSTGRES_PORT=$(POSTGRES_PORT) \
	$(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG) wait-for-it --timeout=60 $1)

.PHONY: black
black:
	docker  run --rm -ti --volume $(PWD):/mnt/code:rw \
		--env PYTHONPATH=/mnt/code \
		$(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG) \
		black .

.PHONY: build-devel
build-devel:
	docker  build --tag $(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG) \
		-f scripts/Dockerfile $(PWD)

.PHONY: build-tika-server
build-tika-server:
	docker  build --tag $(IMAGE_NAMESPACE)/$(APACHE_TIKA_IMAGE_NAME):$(APACHE_TIKA_IMAGE_TAG) \
		-f scripts/Dockerfile_apache_tika $(PWD)

.PHONY: build
build: build-devel build-tika-server

.PHONY: login
login:
	docker  login --username $(REGISTRY_USER) --password "$(REGISTRY_PASSWORD)" https://index.docker.io/v1/

.PHONY: publish
publish:
	docker  tag $(IMAGE_NAMESPACE)/$(IMAGE_NAME):${IMAGE_TAG} $(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(shell date --rfc-3339=date --utc)
	docker  push $(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(shell date --rfc-3339=date --utc)
	docker  push $(IMAGE_NAMESPACE)/$(IMAGE_NAME):${IMAGE_TAG}

.PHONY: destroy
destroy:
	docker  rmi --force $(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG)

destroy-pod:
	docker  pod rm --force  $(POD_NAME)

create-pod: destroy-pod
	docker  pod create -p $(POSTGRES_PORT):$(POSTGRES_PORT) \
					  -p $(ELASTICSEARCH_PORT1):$(ELASTICSEARCH_PORT1) \
					  -p $(STORAGE_PORT):$(STORAGE_PORT) \
	                  --name $(POD_NAME)

prepare-test-env: create-pod storage apache-tika-server elasticsearch database

.PHONY: test
test: prepare-test-env retest

.PHONY: retest
retest:
	$(call run-command, python -m unittest -f tests)

.PHONY: retest-digital-ocean-spaces
retest-digital-ocean-spaces:
	$(call run-command, python -m unittest -f tests/digital_ocean_spaces.py)

.PHONY: retest-postgres
retest-postgres:
	$(call run-command, python -m unittest -f tests/postgresql.py)

.PHONY: retest-tasks
retest-tasks:
	$(call run-command, python -m unittest -f tests/text_extraction_task_tests.py)

.PHONY: retest-main
retest-main:
	$(call run-command, python -m unittest -f tests/main_tests.py)

.PHONY: retest-index
retest-index:
	$(call run-command, python -m unittest -f tests/elasticsearch.py)

.PHONY: retest-tika
retest-tika:
	$(call run-command, python -m unittest -f tests/text_extraction_tests.py)

start-apache-tika-server:
	docker run -d -p 9998:9998 --rm --name tika apache/tika:1.28.4

stop-apache-tika-server:
	docker  stop  $(APACHE_TIKA_CONTAINER_NAME)
	docker  rm --force  $(APACHE_TIKA_CONTAINER_NAME)

.PHONY: apache-tika-server
apache-tika-server: stop-apache-tika-server start-apache-tika-server


shell: set-run-variable-values
	docker  run --rm -ti --volume $(PWD):/mnt/code:rw \
		--env PYTHONPATH=/mnt/code \
		--env-file envvars \
		$(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG) bash

.PHONY: coverage
coverage: prepare-test-env
	$(call run-command, coverage erase)
	$(call run-command, coverage run -m unittest tests)
	$(call run-command, coverage report -m)

.PHONY: stop-storage
stop-storage:
	docker  rm --force  $(STORAGE_CONTAINER_NAME)

.PHONY: storage
storage: stop-storage start-storage wait-storage

start-storage:
	docker run -d --rm -ti \
        --name queridodiario-storage \
        -p 127.0.0.1:9000:9000\
        -e MINIO_ACCESS_KEY=minio-access-key \
        -e MINIO_SECRET_KEY=minio-secret-key \
        -e MINIO_DEFAULT_BUCKETS=queridodiariobucket:public \
        docker.io/bitnami/minio:2021.4.6

wait-storage:
	$(call wait-for, localhost:9000)

.PHONY: stop-database
stop-database:
	docker  rm --force  $(DATABASE_CONTAINER_NAME)

.PHONY: database
database: stop-database start-database wait-database

start-database:
	docker run -d --rm -ti \
        --name queridodiario-db \
        -p 127.0.0.1:5432:5432\
        -e POSTGRES_PASSWORD=queridodiario \
        -e POSTGRES_USER=queridodiario \
        -e POSTGRES_DB=queridodiariodb \
        docker.io/postgres:10

wait-database:
	$(call wait-for, localhost:5432)

load-database: set-run-variable-values
ifneq ("$(wildcard $(DATABASE_RESTORE_FILE))","")
	docker  cp $(DATABASE_RESTORE_FILE) $(DATABASE_CONTAINER_NAME):/mnt/dump_file
	docker  exec $(DATABASE_CONTAINER_NAME) bash -c "pg_restore -v -c -h localhost -U $(POSTGRES_USER) -d $(POSTGRES_DB) /mnt/dump_file || true"
else
	@echo "cannot restore because file does not exists '$(DATABASE_RESTORE_FILE)'"
	@exit 1
endif

set-run-variable-values:
	cp --no-clobber contrib/sample.env envvars || true
	$(eval POD_NAME=run-$(POD_NAME))
	$(eval DATABASE_CONTAINER_NAME=run-$(DATABASE_CONTAINER_NAME))
	$(eval ELASTICSEARCH_CONTAINER_NAME=run-$(ELASTICSEARCH_CONTAINER_NAME))

.PHONY: sql
sql: set-run-variable-values
	docker  run --rm -ti \	
		$(POSTGRES_IMAGE) psql -h localhost -U $(POSTGRES_USER) $(POSTGRES_DB)

.PHONY: setup
setup: start-apache-tika-server start-storage start-elasticsearch start-database

.PHONY: re-run
re-run: set-run-variable-values
	docker  run --rm -ti --net=host --volume $(PWD):/mnt/code:rw \
		--env PYTHONPATH=/mnt/code \
		--env-file envvars \
		$(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG) python main

.PHONY: run
run: setup re-run

.PHONY: shell-run
shell-run: set-run-variable-values
	docker  run --rm -ti --volume $(PWD):/mnt/code:rw \
		--env PYTHONPATH=/mnt/code \
		--env-file envvars \
		$(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_TAG) 

.PHONY: shell-database
shell-database: set-run-variable-values
	docker  exec -it $(DATABASE_CONTAINER_NAME) \
	    psql -h localhost -d $(POSTGRES_DB) -U $(POSTGRES_USER)

elasticsearch: stop-elasticsearch start-elasticsearch wait-elasticsearch

start-elasticsearch:
	docker run -d --rm -ti \
        --name queridodiario-elasticsearch \
        -p 127.0.0.1:9200:9200\
        --env discovery.type=single-node \
        docker.io/elasticsearch:7.9.1

stop-elasticsearch:
	docker  rm --force  $(ELASTICSEARCH_CONTAINER_NAME)

wait-elasticsearch:
	$(call wait-for, localhost:9200)

.PHONY: publish-tag
publish-tag:
	docker  tag $(IMAGE_NAMESPACE)/$(IMAGE_NAME):${IMAGE_TAG} $(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(shell git describe --tags)
	docker  push $(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(shell git describe --tags)
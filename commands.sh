#!/bin/bash

function build() {
	# flags
	COPY_LOCAL=0

	# arguments
	WORKSPACE="workspace"

	for (( i=1; i<=$#; i++ )); do
		ARG="${!i}"
		case "${ARG}" in
			-*)
				for (( j=1; j<${#ARG}; j++ )); do
					FLAG="${ARG:j:1}"

					case "${FLAG}" in
						"l")
							COPY_LOCAL=1
							;;
						*)
							echo "Unknown flag '${FLAG}'"
							exit 1
					esac
				done
				;;
			*)
				if [ $i -eq $# ]; then
					WORKSPACE=${ARG}
				else
					echo "Unknown argument at position ${i} '${!i}'"
					exit 1
				fi
				;;
		esac
	done

	docker build \
		--target build \
		-t "${WORKSPACE}-build:latest" \
		.

	if [ $COPY_LOCAL -eq 1 ]; then
		rm -rf build/build build/install build/log

		CONTAINER=$(docker create "${WORKSPACE}-build:latest")
		docker cp "${CONTAINER}:/home/build/${WORKSPACE}/build" "./build/build"
		docker cp "${CONTAINER}:/home/build/${WORKSPACE}/install" "./build/install"
		docker cp "${CONTAINER}:/home/build/${WORKSPACE}/log" "./build/log"
		docker rm "${CONTAINER}" > /dev/null
	fi
}

function run() {
	# flags
	TARGET="dev"

	# arguments
	WORKSPACE="workspace"

	for (( i=1; i<=$#; i++ )); do
		ARG="${!i}"
		case "${ARG}" in
			-*)
				for (( j=1; j<${#ARG}; j++ )); do
					FLAG="${ARG:j:1}"

					case "${FLAG}" in
						"p")
							TARGET="prod"
							;;
						*)
							echo "Unknown flag '${FLAG}'"
							exit 1
					esac
				done
				;;
			*)
				if [ $i -eq $# ]; then
					WORKSPACE=${ARG}
				else
					echo "Unknown argument at position ${i} '${!i}'"
					exit 1
				fi
				;;
		esac
	done

	docker build \
		--target "runtime" \
		--build-arg TARGET=${TARGET} \
		--tag "${WORKSPACE}-${TARGET}:latest" \
		.

	docker run \
		--attach stdout \
		--attach stderr \
		--name "${WORKSPACE}-${TARGET}" \
		--rm \
		"${WORKSPACE}-${TARGET}:latest"
}

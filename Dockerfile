# Info for the user that the app should run under
ARG USERNAME="Ros2App"
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Relevant info about the workspace
ARG WORKSPACE="workspace"
ARG ROS_DISTRO="humble"

# `dev` or `prod`, decides if debugging tools are added
ARG TARGET="dev"

# Stage 1 - build
# Clean image for building ros projects in
FROM ros:${ROS_DISTRO} AS build

# Import ARGS
ARG WORKSPACE
ARG ROS_DISTRO

SHELL ["/bin/bash", "-c"]

# Create user for the build to run under, let sudo run without password
# build always runs under username build so that it can be accessed by the sh files
RUN groupadd --gid 1000 build
RUN useradd --uid 1000 --gid 1000 --create-home build
RUN echo build ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/build && chmod 0440 /etc/sudoers.d/build
USER build

# Connect to the cache proxy
RUN printf "Acquire::HTTP::Proxy \"http://172.17.0.1:3142\";\nAcquire::HTTPS::Proxy \"false\";\n" \
	| sudo tee /etc/apt/apt.conf.d/10-proxy > /dev/null

# Copy in the package files
COPY --chown=build ${WORKSPACE}/src/*/{package.xml,CMakeLists.txt} /home/build/${WORKSPACE}/
WORKDIR /home/build/${WORKSPACE}

# Update package lists
RUN rosdep update --rosdistro ${ROS_DISTRO}
RUN sudo apt-get update

# Get required build packages
WORKDIR /tmp
COPY --chown=build depends/apt-build.txt /tmp/user-apt-build.txt
RUN sudo sed -i 's/#.*//;/^$/d' /tmp/user-apt-build.txt
RUN rosdep install -y \
	--from-paths "/home/build/${WORKSPACE}" \
	--ignore-src \
	--reinstall \
	--simulate \
	| grep "apt-get install" \
	| awk '{ print $6 }' \
	| sort -u \
	| sudo tee /tmp/workspace-apt-build.txt > /dev/null
RUN cat /tmp/user-apt-build.txt /tmp/workspace-apt-build.txt \
	| xargs -r sudo apt-get install -y \
	&& sudo rm /tmp/user-apt-build.txt /tmp/workspace-apt-build.txt

# While we have rosdep, get a list of runtime dependencies
RUN rosdep install -y \
	--from-paths "/home/build/${WORKSPACE}" \
	--ignore-src \
	--reinstall \
	--simulate \
	--dependency-types=exec \
	| grep "apt-get install" \
	| awk '{ print $6 }' \
	| sort -u > /home/build/runtime-apt.txt

# Copy in the actual source
COPY --chown=build ${WORKSPACE} /home/build/${WORKSPACE}

# Build
WORKDIR /home/build/${WORKSPACE}
RUN source /opt/ros/${ROS_DISTRO}/setup.bash && colcon build --executor sequential

# Cleanup local cache for smaller image
RUN sudo rm -rf \
	/home/build/.ros/rosdep/sources.cache/ \
	/var/lib/apt/lists/*

# Stage 2.a - prod
# Minimal image with just the ros runtime, no build tools
FROM ros:${ROS_DISTRO}-ros-core AS prod

# Import ARGs
ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG WORKSPACE
ARG ROS_DISTRO

SHELL ["/bin/bash", "-c"]

# Create user for the workspace to run under
RUN groupadd --gid ${USER_GID} ${USERNAME}
RUN useradd --uid ${USER_UID} --gid ${USER_GID} --create-home ${USERNAME} --shell "/bin/bash"

# Connect to the cache proxy
RUN printf "Acquire::HTTP::Proxy \"http://172.17.0.1:3142\";\nAcquire::HTTPS::Proxy \"false\";\n" \
	> /etc/apt/apt.conf.d/10-proxy

# update package lists
RUN apt-get update

# get required runtime dependencies
COPY --from=build /home/build/runtime-apt.txt /tmp/workspace-apt-prod.txt
COPY depends/apt-prod.txt /tmp/user-apt-prod.txt
RUN sed -i 's/#.*//;/^$/d' /tmp/user-apt-prod.txt
RUN cat /tmp/user-apt-prod.txt /tmp/workspace-apt-prod.txt \
	| xargs -r apt-get install -y \
	&& rm /tmp/user-apt-prod.txt /tmp/workspace-apt-prod.txt

# Setup bash
RUN printf "\n# Workspace sourcing\nsource /opt/ros/${ROS_DISTRO}/setup.bash\n" >> /home/${USERNAME}/.bashrc

# Cleanup local cache for smaller image
RUN rm -rf \
	/var/lib/apt/lists/*

USER ${USERNAME}

# Stage 2.b - dev
# Install debugging tools and set up tools for debugging
FROM prod AS dev

# Import needed args
ARG USERNAME

# Need to be root to do the next two things and no sudo yet
USER root

# Connect to the cache proxy
RUN printf "Acquire::HTTP::PROXY \"http://172.17.0.1:3142\";\nAcquire::HTTPS::PROXY \"false\";\n" \
	> /etc/apt/apt.conf.d/10-proxy

# Update package lists
RUN apt-get update

# Install sudo, allow use without password, need to switch back to root to do this
RUN apt-get install -y sudo
RUN echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} && chmod 0440 /etc/sudoers.d/${USERNAME}
USER ${USERNAME}

WORKDIR /tmp
COPY depends/apt-dev.txt /tmp/user-apt-dev.txt
RUN sudo sed -i 's/#.*//;/^$/d' /tmp/user-apt-dev.txt && echo "bash-completion" | sudo tee -a /tmp/user-apt-dev.txt > /dev/null
RUN cat /tmp/user-apt-dev.txt \
	| xargs -r sudo apt-get install -y \
	&& sudo rm /tmp/user-apt-dev.txt

# Cleanup local cache for smaller image
RUN sudo rm -rf \
	/var/lib/apt/lists/*

# Stage 3 - runtime
# Copy the runtime onto the image made by either 2.a or 2.b
FROM ${TARGET} AS runtime

# Import needed args
ARG USERNAME
ARG WORKSPACE

WORKDIR /home/${USERNAME}/${WORKSPACE}

COPY --from=build --chown=${USERNAME} "/home/build/${WORKSPACE}/install" "/home/${USERNAME}/${WORKSPACE}/install"

COPY --chown=${USERNAME} "main.sh" "/home/${USERNAME}/main.sh"
RUN chmod +x "/home/${USERNAME}/main.sh"

CMD [ "~/main.sh" ]

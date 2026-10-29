# Info for the user that the app should run under
ARG USERNAME="Ros2App"
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Relevant info about the workspace
ARG WORKSPACE="workspace"
ARG ROS_DISTRO="humble"

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

# get other required build packages
WORKDIR /tmp
COPY --chown=build depends/apt-build.txt /tmp/apt-build.txt
RUN sudo apt-get update -y && sudo apt-get upgrade -y
RUN sed 's/#.*//' /tmp/apt-build.txt | grep . | xargs -r sudo apt-get install -y && rm /tmp/apt-build.txt

# Copy in the source
COPY --chown=build ${WORKSPACE} /home/build/${WORKSPACE}
WORKDIR /home/build/${WORKSPACE}
RUN source /opt/ros/${ROS_DISTRO}/setup.sh
RUN rosdep update && rosdep install -i --from-path src --rosdistro ${ROS_DISTRO} -y
RUN colcon build --executor sequential

# Clean caches to make image smaller
RUN sudo rm -rf /var/lib/apt/lists/*

# Stage 2.a - prod
# Minimal image with just the ros runtime, no build tools
FROM ros:humble-ros-core AS prod

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

# get required runtime dependencies
WORKDIR /tmp
COPY depends/apt-prod.txt /tmp/apt-prod.txt
RUN apt-get update -y && apt-get upgrade -y
RUN sed 's/#.*//' /tmp/apt-prod.txt | grep . | xargs -r apt-get install -y && rm /tmp/apt-prod.txt

# Clean caches
RUN rm -rf /var/lib/apt/lists/*

USER ${USERNAME}

# Setup bash
RUN source /opt/ros/${ROS_DISTRO}/setup.bash
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /home/${USERNAME}/.bashrc

# Stage 2.b - dev
# Install debugging tools and set up tools for debugging
FROM prod AS dev

# Import needed args
ARG USERNAME

# Install sudo, allow use without password, need to switch back to root to do this
USER root
RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install -y sudo
RUN echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} && chmod 0440 /etc/sudoers.d/${USERNAME}
USER ${USERNAME}

# get debugging tools
WORKDIR /tmp
COPY --chown=${USERNAME} depends/apt-dev.txt /tmp/apt-dev.txt
RUN sed 's/#.*//' /tmp/apt-dev.txt | grep . | xargs -r sudo apt-get install -y && sudo rm /tmp/apt-dev.txt

# Clean caches
RUN sudo rm -rf /var/lib/apt/lists/*

# Stage 3 - runtime
# Copy the runtime onto the image made by either 2.a or 2.b
FROM ${TARGET} AS runtime

# Import needed args
ARG USERNAME
ARG WORKSPACE

WORKDIR /home/${USERNAME}/${WORKSPACE}

COPY --from=build --chown=${USERNAME} "/home/build/${WORKSPACE}/install" "/home/${USERNAME}/${WORKSPACE}/install"

RUN source /home/${USERNAME}/${WORKSPACE}/install/setup.bash
RUN echo "source /home/${USERNAME}/${WORKSPACE}/install/setup.bash" >> /home/${USERNAME}/.bashrc

COPY --chown=${USERNAME} "./runtime.sh" "/home/${USERNAME}"
RUN chmod +x "/home/${USERNAME}/runtime.sh"

RUN echo '$USER'

ENV WORKSPACE=${WORKSPACE}
CMD [ "~/runtime.sh" ]

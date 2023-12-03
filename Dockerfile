## Image based in this Dockerfile: https://github.com/eduble/rpi-mini/blob/master/Dockerfile
## with info obtained from here: https://github.com/RPi-Distro/pi-gen

# ------------------------------------------------
# Builder Image: generate a base debian directory
# ------------------------------------------------
FROM debian:bookworm as builder
RUN apt-get update && apt-get install -y mc debootstrap && apt-get clean
WORKDIR /root

RUN debootstrap --foreign --arch=arm64 --include=gnupg,ca-certificates,wget  --components=main,contrib --exclude=info --variant=minbase bookworm fs http://deb.debian.org/debian/

WORKDIR /root/fs
# Save ownership of non-root and files with special permissions (suid, sgid, sticky)
RUN touch .non-root.sh && echo -e '#!/bin/bash\n' >> .non-root.sh && \
    stat -c "chown %u:%g %n" $(find . ! -user root -o ! -group root) >> .non-root.sh && \
    stat -c "chmod %a %n" $(find . -perm /7000) >> .non-root.sh && \
    chmod +x .non-root.sh

# ---------------------------------------------------
# Layered Image: build on this base debian directory
# ---------------------------------------------------
FROM scratch as layered
WORKDIR /

# Copy the subdirectory generated from debootstrap first stage
COPY --from=builder /root/fs .

# We want ARM CPU emulation to work, even if we are running all this
# on the docker hub (automated build) and binfmt_misc is not available.
# So we get the modified qemu built by guys from Multiarch (https://github.com/multiarch/qemu-user-static).
# This modified qemu is able to catch subprocesses creation and handle
# their CPU emulation.
COPY --from=multiarch/qemu-user-static:x86_64-aarch64  /usr/bin/qemu-aarch64-static /usr/bin/

# Restore ownership of non-root files that may have been lost during copy
RUN sh .non-root.sh

# Second stage of debootstrap will try to mount things already mounted,
# do not fail
RUN ln -sf /bin/true /bin/mount

# Call second stage of debootstrap
RUN /debootstrap/debootstrap --second-stage

# Save ownership of non-root and files with special permissions (suid, sgid, sticky)
RUN stat -c "ls -ld %n; chown %u:%g %n" $(find . -xdev ! -user root -o ! -group root) > .non-root.sh && \
    stat -c "ls -ld %n; chmod %a %n" $(find . -xdev -perm /7000) >> .non-root.sh && \
    chmod +x .non-root.sh

# Add Raspberry Pi repositories
ADD raspios.list /etc/apt/sources.list.d/

# Register Raspberry Pi Archive Signing Key
ADD raspberrypi-archive-stable.gpg /usr/share/keyrings/
ADD raspberrypi-archive-stable.gpg /etc/apt/trusted.gpg.d/


# Update pakages installed, with Raspberry Pi versions.
RUN apt-get update --allow-releaseinfo-change && apt-get upgrade -y && apt-get clean

# ---------------------------------------
# Squashed Image: compress layered image
# ---------------------------------------
# We will squash layers into a clean image.
# First stage of debootstrap have created many files that were actually
# removed by the second stage, so our final image can be made at least
# twice smaller than previous one ("layered").
FROM scratch
COPY --from=layered / /

# Change shell, for run arm binaries files
SHELL ["/usr/bin/qemu-aarch64-static", "/bin/bash", "-c"]

# Restore ownership of non-root files that may have been lost during copy
RUN sh .non-root.sh && rm .non-root.sh

RUN apt-get update && apt-get upgrade -y && apt-get install -y mc

# Cleaning...
RUN rm /usr/bin/qemu-aarch64-static

# Return to image shell
SHELL ["/bin/bash", "-c"]

CMD ["/bin/bash"]

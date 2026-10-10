# syntax=docker/dockerfile:1

# A reproducible vcc: the same tree yields the same bytes.
#
# Two of the inputs are pinned so they cannot move underneath the build. V is
# built from the commit ci.yml pins rather than from a release, because the
# 0.5.2 release cannot compile this tree: its checker rejects the `for {}` in
# parser/parser.v (README, "Build and run it"). The base image is pinned by
# digest for the same reason, since an apt package that changes between builds
# changes the gcc that builds V.
#
# Reproducibility. The image is built with `-prod`, which compiles the generated
# C without debug information: the binary carries no .stab and no .stabstr, so
# nothing in it depends on where or when it was built. Measured on this tree:
# two `v -prod -nocache` builds of the same source (the container has no cache
# to reuse), 4,340,520 bytes each, identical sha256.
#
# The strip below is kept as a guard rather than as the thing that makes the
# build reproducible. The plain build does carry the two sections, and the C
# compiler V reaches for decides whether their bytes are stable: tcc writes the
# absolute path of a scratch directory whose name carries a pid, a monotonic
# timestamp and a stack address (vlib/v/tempname) into them, which is why two
# plain builds of the same tree once differed in 26 bytes, all of them inside
# .stabstr. Removing the two sections removes that difference and leaves the
# machine code untouched, and objcopy exits 0 when there is nothing to remove.

FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3 AS build

# The V this tree is built and tested with, as a commit rather than a release
# tag. Kept equal to .github/workflows/ci.yml.
ARG V_COMMIT=a6826c4db0e28d306160fcc9e96baca90ea78f40

ENV DEBIAN_FRONTEND=noninteractive

# make and gcc build V; git clones it and fetches the tcc V vendors; binutils
# supplies objcopy, which strips the debug sections at the end.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      binutils \
      ca-certificates \
      gcc \
      git \
      libc6-dev \
      make \
 && rm -rf /var/lib/apt/lists/*

# Build V at the pinned commit. This step uses the system gcc; vcc itself is
# then built by the tcc and V this produces, not by gcc.
RUN git clone --quiet https://github.com/vlang/v /opt/v \
 && git -C /opt/v checkout --quiet "${V_COMMIT}" \
 && make -C /opt/v
ENV PATH=/opt/v:$PATH

WORKDIR /src
COPY . /src

RUN v -prod -o /vcc . \
 && objcopy --remove-section=.stab --remove-section=.stabstr /vcc

# The artifact is the compiler and nothing else: one file in the image, with no
# build tooling beside it. Copy it out with
#   id=$(docker create IMAGE) && docker cp "$id:/vcc" ./vcc && docker rm "$id"
# The CMD exists so `docker create` accepts the image; a scratch image has no
# libc, so the file is meant to be copied out rather than run in place.
FROM scratch AS artifact
COPY --from=build /vcc /vcc
CMD ["/vcc"]

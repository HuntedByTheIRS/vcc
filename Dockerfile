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
# Reproducibility itself comes from one post-processing step. Everything in the
# default `v -o vcc .` build is deterministic except the debug strings: V
# compiles the generated C in a scratch directory whose name carries a pid, a
# monotonic timestamp and a stack address (vlib/v/tempname), and tcc writes the
# absolute path of the source inside that directory into the .stab and .stabstr
# sections. The name changes every run, so those bytes change every run;
# nothing else does. Dropping the two sections with objcopy removes the only
# difference and leaves the machine code untouched. Measured: two builds of the
# same tree that differ in 26 bytes, all of them inside .stabstr, become
# byte-identical after this step.

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

RUN v -o /vcc . \
 && objcopy --remove-section=.stab --remove-section=.stabstr /vcc

# The artifact is the compiler and nothing else: one file in the image, with no
# build tooling beside it. Copy it out with
#   id=$(docker create IMAGE) && docker cp "$id:/vcc" ./vcc && docker rm "$id"
# The CMD exists so `docker create` accepts the image; a scratch image has no
# libc, so the file is meant to be copied out rather than run in place.
FROM scratch AS artifact
COPY --from=build /vcc /vcc
CMD ["/vcc"]

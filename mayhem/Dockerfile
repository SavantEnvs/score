# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form, PREFERRED) — builds ON TOP of the org C/C++ base
# image (ghcr.io/savantenvs/base). The base already provides debian + clang/llvm +
# libFuzzer/afl++ + the identities + the build-contract ENV, so this only adds the
# per-commit build (built on top of the prebuilt base, rather than building the toolchain in-image).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t mytag .

# The org base, pinned to a fixed DATE-tagged base (YYYYMMDD; shared by all integrations
# minted against it). Use the current dated tag; pin by digest in production: ...base@sha256:<digest>.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an ENV — an
# empty value breaks clang ("must be a non-negative decimal integer") both here and for
# any in-image rebuild. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# Sanitizer override: the base exports SANITIZER_FLAGS (ASan+UBSan, halting) as the default.
# To change it for a build (e.g. ASan-only, or add MSan): --build-arg SANITIZER_FLAGS="...".
# Declare it WITHOUT a default (no '='): an undefaulted ARG lets the base ENV flow through to
# build.sh when not passed, and an explicit --build-arg overrides it. (An empty default — `=` —
# would instead shadow the base ENV and silently wipe the sanitizers.)
ARG SANITIZER_FLAGS
# Coverage (optional, off by default): instrument the TEST build to measure how much of the project
# the suite exercises — --build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping".
# Empty by default (no effect on the normal oracle build); build.sh appends it to the test build only.
ARG COVERAGE_FLAGS=
# Build parallelism (optional). build.sh falls back to nproc when unset: --build-arg MAYHEM_JOBS=8
ARG MAYHEM_JOBS=

# libisf (3rdparty/libisf) needs boost + fmt from apt and four header-only libraries that score
# vendors as git submodules (not checked out in the build context). They are baked in under /opt/deps
# at pinned commits (the ones libossia's own submodules pin, at score's pinned libossia) so
# mayhem/build.sh stays air-gapped and re-runnable.
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        libboost-dev libboost-regex-dev libfmt-dev ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
RUN set -eu; mkdir -p /opt/deps; cd /opt/deps; \
    fetch() { n="$1"; url="$2"; sum="$3"; dir="$4"; strip="${5:-1}"; shift 5 || true; \
        curl -sSfL --retry 5 -o "$n.tgz" "$url"; \
        echo "$sum  $n.tgz" | sha256sum -c -; \
        mkdir -p "$dir"; tar -xzf "$n.tgz" -C "$dir" --strip-components="$strip" "$@"; rm "$n.tgz"; }; \
    fetch libossia https://github.com/ossia/libossia/archive/4dc442774854a03eabcda7fa5f1c47593700957d.tar.gz \
        40e76ed1aaa0dc00f04ce6596085cfa1d87f47fc4feec1af5fd21e0db2eb7730 libossia 1 --wildcards '*/src/*'; \
    fetch ctre https://github.com/hanickadot/compile-time-regular-expressions/archive/e34c26ba149b9fd9c34aa0f678e39739641a0d1e.tar.gz \
        2bf1482da366c7f0461e5cbbdb7a65474cdefe0eb7f8d994c6d79121f09e1806 ctre 1 --wildcards '*/include/*'; \
    fetch unordered_dense https://github.com/jcelerier/unordered_dense/archive/5bdd46cbb988634ecd9642658c4b286cbb626f67.tar.gz \
        0ad70fe5e7b2c0aa42c21fb1d6a65e6f65dffe3376c1994b24cb3631f65264a6 unordered_dense 1 --wildcards '*/include/*'; \
    fetch rapidhash https://github.com/Nicoshev/rapidhash/archive/92731ee0823c7c71890de988f62aabe26ed73aa6.tar.gz \
        baf2960676eb53da2c427ef504eff547df69c4936c6bd9edea4cb72986b969bb rapidhash 1 --wildcards '*/rapidhash.h' '*/secret.h'; \
    ls /opt/deps/*/
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git
# history) is copied to /mayhem as `mayhem`; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Anything a Dockerfile step materializes into the tree (downloaded fixtures, generated headers,
# vendored deps) MUST be committed or (re)created by build.sh: rlenv's patch grader runs
# `git clean -ffdX` before every graded build, so a gitignored, untracked file is gone by then and
# every honest patch scores zero (SPEC §6.2 item 16; verify-repo.sh checks it).
#
# OPTIONAL compile-cache pre-fill (SPEC §6.2 item 18). Bases minted with /opt/mayhem/ccache/prefill
# run the build under rlenv's pinned ccache, so the patch grader's first (otherwise cold) rebuild is
# warm — this is what keeps large C/C++ targets inside the build time limit. Older bases fall back to
# the plain build; a missing or stale pre-fill only costs a cold cache. Never enable ccache in
# build.sh or via ENV/PATH, and keep the compiler resolving by name (CC=clang) or nothing is cached.
RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

# Run the project's functional tests at build time IF the repo ships them (mayhem/test.sh is
# optional — omit it only when the repo has no tests meaningful for RL). A failing suite fails the
# image build, so the commit image is guaranteed to build AND pass its own tests.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem

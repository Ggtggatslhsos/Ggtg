#!/bin/bash
set -euo pipefail

# Safe/explicit version of tt.sh
# - Requires explicit consent via ALLOW_MINING=yes
# - Provides a DRY_RUN mode that prints steps instead of executing them
# - Removes deceptive behavior (process renaming, output masking)
# - Lowers process priority so it is less disruptive
# - Keeps SKIP_INSTALL option to allow offline/local builds

# Require explicit consent
if [ "${ALLOW_MINING:-no}" != "yes" ]; then
  echo "Consent required. Set ALLOW_MINING=yes to run this script. Exiting."
  exit 1
fi

# Dry run mode: if DRY_RUN=yes then commands will be printed instead of executed
DRY_RUN="${DRY_RUN:-no}"
run_cmd() {
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[DRY_RUN] $*"
  else
    eval "$*"
  fi
}

# Lower priority so it is less disruptive
renice -n 10 $$ >/dev/null 2>&1 || true

# --- Install dependencies (skip if SKIP_INSTALL=1) ---
if [ "${SKIP_INSTALL:-0}" = "1" ]; then
  echo "SKIP_INSTALL=1 set; skipping package installation."
else
  echo "Updating package lists and installing build deps (may require sudo)..."
  run_cmd sudo apt-get update
  set +e
  run_cmd sudo apt-get install -y build-essential cmake libuv1-dev libssl-dev libhwloc-dev
  install_rc=$?
  set -e
  if [ "$install_rc" -ne 0 ]; then
    echo "Warning: some packages failed to install. Continuing..."
  fi
fi

# --- Clone and build XMRig (with local deps if needed) ---
if [ ! -d "xmrig/.git" ]; then
  echo "Cloning xmrig..."
  run_cmd rm -rf xmrig
  run_cmd git clone https://github.com/xmrig/xmrig.git
fi

cd xmrig

# Build only if the xmrig binary doesn't exist or isn't executable
if [ ! -x "build/xmrig" ]; then
  if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    if [ -x "./scripts/build.uv.sh" ]; then
      run_cmd ./scripts/build.uv.sh
    fi
    if [ -x "./scripts/build.hwloc.sh" ]; then
      run_cmd ./scripts/build.hwloc.sh
    fi
  fi

  CMAKE_OPTS=""
  if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    if [ -f "deps/lib/libuv.a" ] && [ -d "deps/include" ]; then
      CMAKE_OPTS="${CMAKE_OPTS} -DUV_LIBRARY=${PWD}/deps/lib/libuv.a -DUV_INCLUDE_DIR=${PWD}/deps/include"
    fi
    if [ -f "deps/lib/libhwloc.a" ] && [ -d "deps/include" ]; then
      CMAKE_OPTS="${CMAKE_OPTS} -DHWLOC_LIBRARY=${PWD}/deps/lib/libhwloc.a -DHWLOC_INCLUDE_DIR=${PWD}/deps/include"
    else
      CMAKE_OPTS="${CMAKE_OPTS} -DWITH_HWLOC=OFF"
    fi
  fi

  echo "Running cmake and build (cmake opts: $CMAKE_OPTS)"
  run_cmd cmake -S . -B build ${CMAKE_OPTS}
  run_cmd cmake --build build -j"$(nproc)"
fi

# --- Parameters (must be provided via environment in most cases) ---
POOL="${POOL:-stratum+tcp://zeph.2miners.com:2222}"
WALLET="${WALLET:-ZEPHYR2XeiFAkpJC4yaZYFPYe7ony9tJpjGKMowFz1cVU4czwRZrSvp5a1czjQMEU1dXDW9oKk7NK3DiJ8rNgxNZRLMrq8Li4Xe3Y}"
PASS="${PASS:-x}"

# Threads and donate level
XMRIG_THREADS="${XMRIG_THREADS:-$(nproc)}"
XMRIG_DONATE="${XMRIG_DONATE:-1}"

# Build command (do NOT rename the binary; run it directly)
CMD=("./build/xmrig" -a rx/0 -o "${POOL}")
CMD+=( -u "${WALLET}" -p "${PASS}" )
CMD+=( -t "${XMRIG_THREADS}" --donate-level "${XMRIG_DONATE}" --cpu-priority 4 )

# Optional --quiet to reduce output if desired; keep it commented by default
# CMD+=( --quiet )

echo "Starting xmrig with threads=${XMRIG_THREADS} (ensure you have consent and required permissions)"

# Print command in DRY_RUN or run it
if [ "$DRY_RUN" = "yes" ]; then
  echo "Command: ${CMD[*]}"
else
  exec "${CMD[@]}"
fi

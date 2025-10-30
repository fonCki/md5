#!/usr/bin/env bash
# Native builder for HashClash md5 tools on macOS/Linux (no Docker).
# Focuses on producing bin/md5_fastcoll and bin/md5_textcoll.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
VENDOR="${ROOT}/.vendor/hashclash"
BIN="${VENDOR}/bin"
SCRIPTS="${VENDOR}/scripts"
SRC="${VENDOR}/src"

mkdir -p "${BIN}" "${SCRIPTS}"
rm -rf "${SRC}"

echo "[*] Cloning HashClash into ${SRC} ..."
git clone --depth=1 https://github.com/cr-marcstevens/hashclash "${SRC}"

# CPU count
if command -v nproc >/dev/null 2>&1; then
  NJOBS="$(nproc)"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  NJOBS="$(sysctl -n hw.ncpu)"
else
  NJOBS=2
fi

# Toolchain hints
if [[ "$(uname -s)" == "Darwin" ]]; then
  export CC="${CC:-clang}"
  export CXX="${CXX:-clang++}"
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "[!] Command Line Tools missing. Run: xcode-select --install" >&2
  fi
fi

# Critical flags: silence Boost/MPL enum constexpr warnings on recent Clang.
# (This was the error you hit: -Wenum-constexpr-conversion)
CXXFLAGS_COMMON="-O3 -std=c++11 -DNDEBUG -Wno-enum-constexpr-conversion -Wno-deprecated-declarations -Wno-deprecated"
export CXXFLAGS="${CXXFLAGS_COMMON}"

echo "[*] Bootstrapping autotools ..."
(
  cd "${SRC}"
  autoreconf --install
)

# Ensure a local Boost if the tree expects it (preferred path used by HashClash)
if [[ ! -d "${SRC}/boost-1.72.0" ]]; then
  echo "[*] Building local Boost (1.72.0) — first time only ..."
  (
    cd "${SRC}"
    ./install_boost.sh
  )
fi

BOOST_ARG=""
if [[ -d "${SRC}/boost-1.72.0" ]]; then
  BOOST_ARG="--with-boost=${SRC}/boost-1.72.0"
fi

echo "[*] Configuring ..."
(
  cd "${SRC}"
  ./configure ${BOOST_ARG} CXXFLAGS="${CXXFLAGS_COMMON}"
)

echo "[*] Building md5 tools only ..."
(
  cd "${SRC}"
  make -j"${NJOBS}" CXXFLAGS="${CXXFLAGS_COMMON}" bin/md5_fastcoll bin/md5_textcoll
)

echo "[*] Installing binaries ..."
cp -f "${SRC}/bin/md5_fastcoll"* "${BIN}/" 2>/dev/null || true
cp -f "${SRC}/bin/md5_textcoll"* "${BIN}/" 2>/dev/null || true

if [[ ! -x "${BIN}/md5_fastcoll" ]]; then
  echo "[X] md5_fastcoll was not produced. Please scroll up for the first compile error." >&2
  exit 2
fi

echo "[*] Installing scripts ..."
cp -a "${SRC}/scripts/." "${SCRIPTS}/" 2>/dev/null || true

# macOS convenience: provide nproc shim
if [[ "$(uname -s)" == "Darwin" && ! -x "${BIN}/nproc" ]]; then
  cat > "${BIN}/nproc" <<'SH'
#!/usr/bin/env bash
sysctl -n hw.ncpu
SH
  chmod +x "${BIN}/nproc"
fi

echo "[*] HashClash installed under: ${VENDOR}"
echo "    bin:     ${BIN}"
echo "    scripts: ${SCRIPTS}"
echo "export PATH=\"${BIN}:\$PATH\""
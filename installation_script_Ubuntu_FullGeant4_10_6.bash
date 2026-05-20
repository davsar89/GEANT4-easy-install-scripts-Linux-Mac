#!/usr/bin/env bash
set -Eeuo pipefail

trap 'die "Command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
START_DIR="${PWD}"

EXPECT_UBUNTU_VERSION=""
WORK_DIR="${SCRIPT_DIR}/geant4"
JOBS=""
SKIP_DEPS=false
UPDATE_SHELL_RC=true
CLEAN=false
DRY_RUN=false

GEANT4_VERSION="10.6.3"
GEANT4_PATCH_VERSION="10.6.p03"
GEANT4_INTERNAL_VERSION="10.06.p03"
GEANT4_EXTRACTED_DIR_NAME="geant4.${GEANT4_INTERNAL_VERSION}"
GEANT4_ARCHIVE="geant4.${GEANT4_INTERNAL_VERSION}.tar.gz"
GEANT4_URL="https://geant4-data.web.cern.ch/releases/${GEANT4_ARCHIVE}"
GEANT4_SHA256="0b5f13672e7250047b66ffb056c6cfda328a956278cfe61a3fd5dde0672ffbf3"

CMAKE_MINIMUM_VERSION="3.8.0"
CMAKE_VERSION="3.14.3"
CMAKE_PLATFORM="Linux-x86_64"
CMAKE_ARCHIVE="cmake-${CMAKE_VERSION}-${CMAKE_PLATFORM}.tar.gz"
CMAKE_EXTRACTED_DIR="cmake-${CMAKE_VERSION}-${CMAKE_PLATFORM}"
CMAKE_DOWNLOAD_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${CMAKE_ARCHIVE}"
CMAKE_SHA256="29faa62fb3a0b6323caa3d9557e1a5f1205614c0d4c5c2a9917f16a74f7eff68"

XERCES_VERSION="3.2.2"
XERCES_SOURCE_DIR_NAME="xerces-c-${XERCES_VERSION}"
XERCES_ARCHIVE="${XERCES_SOURCE_DIR_NAME}.tar.gz"
XERCES_URL="https://archive.apache.org/dist/xerces/c/3/sources/${XERCES_ARCHIVE}"
XERCES_SHA256="dd6191f8aa256d3b4686b64b0544eea2b450d98b4254996ffdfe630e0c610413"

UBUNTU_VERSION=""
UBUNTU_CODENAME=""

BASE_DIR=""
CMAKE_DIR=""
CMAKE_PATH=""
CMAKE_COMMAND=""
CMAKE_SOURCE=""
GEANT4_SOURCE_DIR=""
GEANT4_BUILD_DIR=""
GEANT4_INSTALL_DIR=""
XERCES_SOURCE_DIR=""
XERCES_BUILD_DIR=""
XERCES_INSTALL_DIR=""
XERCES_INCLUDE_DIR=""
XERCES_LIBRARY=""
ENV_FILE=""

UBUNTU_DEPENDENCIES=()

log() {
    printf '[geant4-10.6-install] %s\n' "$*"
}

warn() {
    printf '[geant4-10.6-install] warning: %s\n' "$*" >&2
}

die() {
    printf '[geant4-10.6-install] error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  installation_script_Ubuntu_FullGeant4_10_6.bash [options]

Options:
  --expect-ubuntu VERSION  Abort unless detected Ubuntu VERSION matches.
  --work-dir PATH          Build/install workspace. Default: repo-local geant4/.
  --jobs N                 Parallel build jobs. Default: auto-detected CPU count.
  --skip-deps              Do not install dependencies; fail if any are missing.
  --no-update-shell-rc     Do not modify ~/.bashrc.
  --clean                  Remove previous generated dirs for this version first.
  --dry-run                Print configuration and actions without changing files.
  -h, --help               Show this help.
EOF
}

absolute_path() {
    local path="$1"

    if [[ "$path" == "/" ]]; then
        printf '/\n'
    elif [[ "$path" == /* ]]; then
        printf '%s\n' "${path%/}"
    else
        printf '%s\n' "${START_DIR}/${path%/}"
    fi
}

parse_args() {
    while (($#)); do
        case "$1" in
            --expect-ubuntu)
                [[ $# -ge 2 && -n "$2" ]] || die "--expect-ubuntu requires a version"
                EXPECT_UBUNTU_VERSION="$2"
                shift 2
                ;;
            --work-dir)
                [[ $# -ge 2 && -n "$2" ]] || die "--work-dir requires a path"
                WORK_DIR="$2"
                shift 2
                ;;
            --jobs)
                [[ $# -ge 2 && -n "$2" ]] || die "--jobs requires a positive integer"
                [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
                JOBS="$2"
                shift 2
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --no-update-shell-rc)
                UPDATE_SHELL_RC=false
                shift
                ;;
            --clean)
                CLEAN=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '[geant4-10.6-install] dry-run:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

run_in_dir() {
    local dir="$1"
    shift

    if [[ "$DRY_RUN" == true ]]; then
        printf '[geant4-10.6-install] dry-run: cd %q &&' "$dir"
        printf ' %q' "$@"
        printf '\n'
    else
        (cd "$dir" && "$@")
    fi
}

version_ge() {
    local candidate="$1"
    local minimum="$2"
    local lowest

    lowest="$(printf '%s\n%s\n' "$minimum" "$candidate" | sort -V | head -n1)"
    [[ "$lowest" == "$minimum" ]]
}

detect_ubuntu_version() {
    [[ -f /etc/os-release ]] || die "Cannot determine OS: /etc/os-release not found"

    # shellcheck source=/etc/os-release
    . /etc/os-release

    [[ "${ID:-}" == "ubuntu" ]] || die "This installer only supports Ubuntu; detected '${NAME:-unknown}'"
    UBUNTU_VERSION="${VERSION_ID:-}"
    UBUNTU_CODENAME="${VERSION_CODENAME:-unknown}"

    case "$UBUNTU_VERSION" in
        18.04)
            ;;
        *)
            die "Unsupported Ubuntu version '${UBUNTU_VERSION}'. This Geant4 10.6 installer supports Ubuntu 18.04."
            ;;
    esac

    if [[ -n "$EXPECT_UBUNTU_VERSION" && "$UBUNTU_VERSION" != "$EXPECT_UBUNTU_VERSION" ]]; then
        die "This wrapper expects Ubuntu ${EXPECT_UBUNTU_VERSION}, but detected Ubuntu ${UBUNTU_VERSION}"
    fi
}

set_ubuntu_profile() {
    UBUNTU_DEPENDENCIES=(
        "build-essential"
        "ca-certificates"
        "cmake"
        "cmake-qt-gui"
        "wget"
        "tar"
        "gzip"
        "make"
        "gcc"
        "g++"
        "gfortran"
        "zlib1g-dev"
        "libx11-dev"
        "libxext-dev"
        "libexpat1-dev"
        "libxmu-dev"
        "libxt-dev"
        "libmotif-dev"
        "libboost-filesystem-dev"
        "libeigen3-dev"
        "libuuid1"
        "uuid-dev"
        "uuid-runtime"
        "qtcreator"
        "qtbase5-dev"
        "qt5-qmake"
        "libqt5opengl5-dev"
        "libgl1-mesa-dev"
        "libglu1-mesa-dev"
    )
}

detect_jobs() {
    if [[ -n "$JOBS" ]]; then
        return
    fi

    if command -v nproc >/dev/null 2>&1; then
        JOBS="$(nproc)"
    elif [[ -r /proc/cpuinfo ]]; then
        JOBS="$(grep -c '^processor' /proc/cpuinfo || true)"
    fi

    if [[ -z "$JOBS" || ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
        JOBS="1"
    fi
}

configure_paths() {
    WORK_DIR="$(absolute_path "$WORK_DIR")"
    [[ "$WORK_DIR" != "/" ]] || die "Refusing to use / as the work directory"

    BASE_DIR="$WORK_DIR"
    CMAKE_DIR="${BASE_DIR}/cmake"
    CMAKE_PATH="${CMAKE_DIR}/bin/cmake"

    GEANT4_SOURCE_DIR="${BASE_DIR}/source_geant4.${GEANT4_INTERNAL_VERSION}"
    GEANT4_BUILD_DIR="${BASE_DIR}/geant4_build_${GEANT4_INTERNAL_VERSION}"
    GEANT4_INSTALL_DIR="${BASE_DIR}/geant4_install_${GEANT4_INTERNAL_VERSION}"

    XERCES_SOURCE_DIR="${BASE_DIR}/source_${XERCES_SOURCE_DIR_NAME}"
    XERCES_BUILD_DIR="${BASE_DIR}/build_xercesc_g4_${GEANT4_INTERNAL_VERSION}"
    XERCES_INSTALL_DIR="${BASE_DIR}/install_xercesc_g4_${GEANT4_INTERNAL_VERSION}"
    XERCES_INCLUDE_DIR="${XERCES_INSTALL_DIR}/include"

    ENV_FILE="${BASE_DIR}/geant4_10_6_env.sh"
}

select_cmake_command() {
    local system_cmake=""
    local system_version=""

    if system_cmake="$(command -v cmake 2>/dev/null)"; then
        system_version="$("$system_cmake" --version | awk '/^cmake version / {print $3; exit}')"
        if [[ -n "$system_version" ]] && version_ge "$system_version" "$CMAKE_MINIMUM_VERSION"; then
            CMAKE_COMMAND="$system_cmake"
            CMAKE_SOURCE="system ${system_version}"
            return
        fi

        warn "System CMake ${system_version:-unknown} is older than ${CMAKE_MINIMUM_VERSION}; will use bundled CMake ${CMAKE_VERSION}."
    fi

    CMAKE_COMMAND="$CMAKE_PATH"
    CMAKE_SOURCE="bundled ${CMAKE_VERSION}"
}

print_configuration() {
    cat <<EOF
[geant4-10.6-install] Configuration
  Ubuntu:        ${UBUNTU_VERSION} (${UBUNTU_CODENAME})
  Geant4:        ${GEANT4_VERSION} (${GEANT4_PATCH_VERSION})
  Xerces-C:      ${XERCES_VERSION}
  CMake:         ${CMAKE_SOURCE} (${CMAKE_COMMAND})
  Work dir:      ${BASE_DIR}
  Jobs:          ${JOBS}
  Install dir:   ${GEANT4_INSTALL_DIR}
  Env file:      ${ENV_FILE}
  Update bashrc: ${UPDATE_SHELL_RC}
  Clean first:   ${CLEAN}
  Skip deps:     ${SKIP_DEPS}
EOF
}

print_dry_run_plan() {
    cat <<EOF
[geant4-10.6-install] Dry-run package profile
  ${UBUNTU_DEPENDENCIES[*]}

[geant4-10.6-install] Dry-run major actions
  1. Check/install apt dependencies for Ubuntu ${UBUNTU_VERSION}.
  2. Prepare workspace: ${BASE_DIR}
  3. Use ${CMAKE_SOURCE}; download bundled CMake only if the system CMake is too old.
  4. Download, SHA256-verify, build, and install Xerces-C ${XERCES_VERSION}.
  5. Download, SHA256-verify, patch if needed, build, and install Geant4 ${GEANT4_VERSION}.
  6. Write environment file: ${ENV_FILE}
  7. Update ~/.bashrc: ${UPDATE_SHELL_RC}
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

check_core_commands() {
    local command
    for command in awk grep sed sort tar gzip sha256sum wget; do
        require_command "$command"
    done
}

missing_dependencies() {
    local package
    for package in "${UBUNTU_DEPENDENCIES[@]}"; do
        if ! dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | grep -q '^install ok installed$'; then
            printf '%s\n' "$package"
        fi
    done
}

check_dependencies() {
    require_command dpkg-query

    local missing=()
    mapfile -t missing < <(missing_dependencies)

    if ((${#missing[@]} == 0)); then
        log "All apt dependencies are installed."
        return
    fi

    warn "Missing apt dependencies: ${missing[*]}"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would ask to install missing dependencies."
        return
    fi

    if [[ "$SKIP_DEPS" == true ]]; then
        die "Missing dependencies and --skip-deps was requested: ${missing[*]}"
    fi

    if [[ ! -t 0 ]]; then
        die "Missing dependencies but no interactive terminal is available for confirmation"
    fi

    local answer
    read -r -p "Install missing dependencies with sudo apt-get? [Y/n]: " answer
    answer="${answer:-Y}"

    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        die "Missing dependencies are required for compilation"
    fi

    sudo -v
    run sudo apt-get update
    run sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

ensure_supported_cmake_download_architecture() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64 | amd64)
            ;;
        *)
            die "Bundled CMake download supports x86_64 only; detected '${arch}'"
            ;;
    esac
}

ensure_inside_workspace() {
    local target="$1"

    case "$target" in
        "${BASE_DIR}/"*) ;;
        *) die "Refusing to remove path outside workspace: ${target}" ;;
    esac
}

remove_generated_path() {
    local target="$1"
    ensure_inside_workspace "$target"

    if [[ -e "$target" || -L "$target" ]]; then
        run rm -rf -- "$target"
    fi
}

clean_previous_outputs() {
    log "Cleaning previous generated outputs for Geant4 ${GEANT4_VERSION}."

    if [[ "$CMAKE_COMMAND" == "$CMAKE_PATH" ]]; then
        remove_generated_path "$CMAKE_DIR"
        remove_generated_path "${BASE_DIR}/${CMAKE_ARCHIVE}"
        remove_generated_path "${BASE_DIR}/${CMAKE_EXTRACTED_DIR}"
    fi

    remove_generated_path "$XERCES_SOURCE_DIR"
    remove_generated_path "${BASE_DIR}/${XERCES_SOURCE_DIR_NAME}"
    remove_generated_path "${BASE_DIR}/${XERCES_ARCHIVE}"
    remove_generated_path "$XERCES_BUILD_DIR"
    remove_generated_path "$XERCES_INSTALL_DIR"

    remove_generated_path "$GEANT4_SOURCE_DIR"
    remove_generated_path "${BASE_DIR}/${GEANT4_ARCHIVE}"
    remove_generated_path "${BASE_DIR}/${GEANT4_EXTRACTED_DIR_NAME}"
    remove_generated_path "$GEANT4_BUILD_DIR"
    remove_generated_path "$GEANT4_INSTALL_DIR"
    remove_generated_path "$ENV_FILE"
}

verify_sha256() {
    local file="$1"
    local expected="$2"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would verify SHA256 for ${file}"
        return
    fi

    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || die "SHA256 mismatch for ${file}: expected ${expected}, got ${actual}"
}

download_file() {
    local url="$1"
    local output="$2"
    local sha256="$3"

    ensure_inside_workspace "$output"
    log "Downloading ${url}"
    remove_generated_path "$output"
    run wget --tries=3 --timeout=30 -O "$output" "$url"
    verify_sha256 "$output" "$sha256"
}

extract_archive() {
    local archive="$1"
    local extracted_name="$2"
    local source_dir="$3"

    ensure_inside_workspace "$archive"
    ensure_inside_workspace "$source_dir"

    remove_generated_path "$source_dir"
    remove_generated_path "${BASE_DIR}/${extracted_name}"
    run tar -xzf "$archive" -C "$BASE_DIR"
    run mv "${BASE_DIR}/${extracted_name}" "$source_dir"

    [[ "$DRY_RUN" == true || -d "$source_dir" ]] || die "Source directory missing after extraction: ${source_dir}"
}

setup_bundled_cmake() {
    if [[ "$CMAKE_COMMAND" != "$CMAKE_PATH" ]]; then
        log "Using system CMake: ${CMAKE_COMMAND}"
        return
    fi

    log "Setting up bundled CMake ${CMAKE_VERSION}."
    ensure_supported_cmake_download_architecture

    remove_generated_path "$CMAKE_DIR"
    download_file "$CMAKE_DOWNLOAD_URL" "${BASE_DIR}/${CMAKE_ARCHIVE}" "$CMAKE_SHA256"
    extract_archive "${BASE_DIR}/${CMAKE_ARCHIVE}" "$CMAKE_EXTRACTED_DIR" "$CMAKE_DIR"
    remove_generated_path "${BASE_DIR}/${CMAKE_ARCHIVE}"

    [[ "$DRY_RUN" == true || -x "$CMAKE_PATH" ]] || die "CMake executable not found at ${CMAKE_PATH}"
}

prepare_directories() {
    run mkdir -p "$BASE_DIR"
    run mkdir -p "$GEANT4_BUILD_DIR" "$GEANT4_INSTALL_DIR" "$XERCES_BUILD_DIR" "$XERCES_INSTALL_DIR"
}

build_xerces() {
    local existing_library=""

    existing_library="$(find_xerces_library)"
    if [[ -f "${XERCES_INCLUDE_DIR}/xercesc/util/PlatformUtils.hpp" && -n "$existing_library" ]]; then
        log "Using existing Xerces-C ${XERCES_VERSION}: ${existing_library}"
        return
    fi

    log "Building Xerces-C ${XERCES_VERSION}."

    download_file "$XERCES_URL" "${BASE_DIR}/${XERCES_ARCHIVE}" "$XERCES_SHA256"
    extract_archive "${BASE_DIR}/${XERCES_ARCHIVE}" "$XERCES_SOURCE_DIR_NAME" "$XERCES_SOURCE_DIR"
    remove_generated_path "${BASE_DIR}/${XERCES_ARCHIVE}"
    remove_generated_path "$XERCES_BUILD_DIR"
    remove_generated_path "$XERCES_INSTALL_DIR"
    run mkdir -p "$XERCES_BUILD_DIR" "$XERCES_INSTALL_DIR"

    run_in_dir "$XERCES_BUILD_DIR" "$CMAKE_COMMAND" \
        -DCMAKE_INSTALL_PREFIX="$XERCES_INSTALL_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        "$XERCES_SOURCE_DIR"
    run "$CMAKE_COMMAND" --build "$XERCES_BUILD_DIR" -- -j"$JOBS"
    run "$CMAKE_COMMAND" --build "$XERCES_BUILD_DIR" --target install
}

find_xerces_library() {
    local library=""

    if [[ -d "$XERCES_INSTALL_DIR" ]]; then
        library="$(find "$XERCES_INSTALL_DIR" \( -type f -o -type l \) 2>/dev/null | grep -E '/libxerces-c[^/]*\.so(\.[0-9.]+)?$' | sort -V | head -n1 || true)"
    fi

    printf '%s\n' "$library"
}

resolve_xerces_library() {
    local library=""

    library="$(find_xerces_library)"
    if [[ -n "$library" ]]; then
        printf '%s\n' "$library"
        return
    fi

    die "Could not resolve installed Xerces-C shared library under ${XERCES_INSTALL_DIR}"
}

patch_geant4_cstdint() {
    log "Checking Geant4 CLHEP RandomEngine.h cstdint include."

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would patch RandomEngine.h if <cstdint> is missing."
        return
    fi

    local files=()
    mapfile -t files < <(find "$GEANT4_SOURCE_DIR" -type f -name RandomEngine.h)

    if ((${#files[@]} == 0)); then
        warn "RandomEngine.h not found under ${GEANT4_SOURCE_DIR}; continuing without patch"
        return
    fi

    local file
    for file in "${files[@]}"; do
        if grep -qE '^[[:space:]]*#[[:space:]]*include[[:space:]]*<cstdint>' "$file"; then
            log "RandomEngine.h already includes <cstdint>: ${file}"
            continue
        fi

        if grep -q '^#define HepRandomEngine_h 1$' "$file"; then
            sed -i '/^#define HepRandomEngine_h 1$/a #include <cstdint>' "$file"
            log "Added <cstdint> include to ${file}"
        else
            warn "Could not find HepRandomEngine_h define in ${file}; continuing without patch"
        fi
    done
}

build_geant4() {
    log "Building Geant4 ${GEANT4_VERSION}."

    download_file "$GEANT4_URL" "${BASE_DIR}/${GEANT4_ARCHIVE}" "$GEANT4_SHA256"
    extract_archive "${BASE_DIR}/${GEANT4_ARCHIVE}" "$GEANT4_EXTRACTED_DIR_NAME" "$GEANT4_SOURCE_DIR"
    remove_generated_path "${BASE_DIR}/${GEANT4_ARCHIVE}"
    remove_generated_path "$GEANT4_BUILD_DIR"
    remove_generated_path "$GEANT4_INSTALL_DIR"
    run mkdir -p "$GEANT4_BUILD_DIR" "$GEANT4_INSTALL_DIR"

    patch_geant4_cstdint

    XERCES_LIBRARY="$(resolve_xerces_library)"
    log "Using Xerces-C library: ${XERCES_LIBRARY}"

    run_in_dir "$GEANT4_BUILD_DIR" "$CMAKE_COMMAND" \
        -DCMAKE_PREFIX_PATH="$XERCES_INSTALL_DIR" \
        -DCMAKE_INSTALL_PREFIX="$GEANT4_INSTALL_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGEANT4_BUILD_MULTITHREADED=OFF \
        -DGEANT4_BUILD_CXXSTD=c++11 \
        -DGEANT4_INSTALL_DATA=ON \
        -DGEANT4_USE_GDML=ON \
        -DGEANT4_USE_G3TOG4=ON \
        -DGEANT4_USE_QT=ON \
        -DGEANT4_FORCE_QT4=OFF \
        -DGEANT4_USE_XM=ON \
        -DGEANT4_USE_OPENGL_X11=ON \
        -DGEANT4_USE_INVENTOR=OFF \
        -DGEANT4_USE_RAYTRACER_X11=ON \
        -DGEANT4_USE_SYSTEM_CLHEP=OFF \
        -DGEANT4_USE_SYSTEM_EXPAT=ON \
        -DGEANT4_USE_SYSTEM_ZLIB=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DXERCESC_ROOT_DIR="$XERCES_INSTALL_DIR" \
        -DXERCESC_INCLUDE_DIR="$XERCES_INCLUDE_DIR" \
        -DXERCESC_LIBRARY="$XERCES_LIBRARY" \
        -DXercesC_INCLUDE_DIR="$XERCES_INCLUDE_DIR" \
        -DXercesC_LIBRARY="$XERCES_LIBRARY" \
        -DXercesC_LIBRARY_RELEASE="$XERCES_LIBRARY" \
        "$GEANT4_SOURCE_DIR"
    run "$CMAKE_COMMAND" --build "$GEANT4_BUILD_DIR" -- -j"$JOBS"
    run "$CMAKE_COMMAND" --build "$GEANT4_BUILD_DIR" --target install
}

write_environment_file() {
    log "Writing environment file: ${ENV_FILE}"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would write ${ENV_FILE}"
        return
    fi

    cat >"$ENV_FILE" <<EOF
# Generated by installation_script_Ubuntu_FullGeant4_10_6.bash
# shellcheck shell=bash

if [ -f "${GEANT4_INSTALL_DIR}/bin/geant4.sh" ]; then
    # shellcheck source=/dev/null
    source "${GEANT4_INSTALL_DIR}/bin/geant4.sh"
fi

export XERCESC_ROOT_DIR="${XERCES_INSTALL_DIR}"
export XercesC_ROOT="${XERCES_INSTALL_DIR}"
export C_INCLUDE_PATH="\${C_INCLUDE_PATH:+\${C_INCLUDE_PATH}:}${XERCES_INSTALL_DIR}/include"
export CPLUS_INCLUDE_PATH="\${CPLUS_INCLUDE_PATH:+\${CPLUS_INCLUDE_PATH}:}${XERCES_INSTALL_DIR}/include"
export LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:+\${LD_LIBRARY_PATH}:}${XERCES_INSTALL_DIR}/lib64"
export LIBRARY_PATH="\${LIBRARY_PATH:+\${LIBRARY_PATH}:}${XERCES_INSTALL_DIR}/lib64"
export PKG_CONFIG_PATH="\${PKG_CONFIG_PATH:+\${PKG_CONFIG_PATH}:}${XERCES_INSTALL_DIR}/lib64/pkgconfig"
EOF
}

remove_marker_block() {
    local file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local first_line=""
    local last_line=""

    while true; do
        first_line="$(grep -nF "$start_marker" "$file" | head -n1 | cut -d: -f1 || true)"
        last_line="$(grep -nF "$end_marker" "$file" | head -n1 | cut -d: -f1 || true)"

        if [[ -z "$first_line" || -z "$last_line" ]]; then
            break
        fi

        if ((first_line > last_line)); then
            warn "Found malformed shell rc marker block in ${file}; leaving it unchanged"
            break
        fi

        sed -i.bak "${first_line},${last_line}d" "$file"
    done
}

update_shell_rc() {
    if [[ "$UPDATE_SHELL_RC" != true ]]; then
        log "Skipping ~/.bashrc update."
        return
    fi

    local bashrc="${HOME}/.bashrc"
    local start_marker="## --> Added by Geant4 10.6 installation script"
    local end_marker="## <-- Added by Geant4 10.6 installation script"
    local old_start_marker="## --> Added by Geant4 installation script"
    local old_end_marker="## <-- Added by Geant4 installation script"

    log "Updating ${bashrc} with managed Geant4 10.6 environment block."

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would update ${bashrc} to source ${ENV_FILE}"
        return
    fi

    touch "$bashrc"
    remove_marker_block "$bashrc" "$old_start_marker" "$old_end_marker"
    remove_marker_block "$bashrc" "$start_marker" "$end_marker"

    {
        printf '\n%s\n' "$start_marker"
        printf 'source %q\n' "$ENV_FILE"
        printf '%s\n' "$end_marker"
    } >>"$bashrc"
}

main() {
    parse_args "$@"
    detect_ubuntu_version
    set_ubuntu_profile
    detect_jobs
    configure_paths
    select_cmake_command
    print_configuration

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run_plan
        check_dependencies
        log "Dry run complete."
        return
    fi

    prepare_directories
    check_dependencies
    check_core_commands

    if [[ "$CLEAN" == true ]]; then
        clean_previous_outputs
        prepare_directories
    fi

    setup_bundled_cmake
    build_xerces
    build_geant4
    write_environment_file
    update_shell_rc

    log "Done. Run 'source ~/.bashrc' or open a new terminal to load Geant4 10.6."
}

main "$@"

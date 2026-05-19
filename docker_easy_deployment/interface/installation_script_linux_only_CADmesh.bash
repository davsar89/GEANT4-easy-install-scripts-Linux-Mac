#!/usr/bin/env bash
set -Eeuo pipefail

GEANT4_VERSION="10.7.4"
GEANT4_INTERNAL_VERSION="10.07.p04"

BASE_DIR="/geant4"
JOBS=""
DRY_RUN=false
UPDATE_SHELL_RC=true

CADMESH_REPO_URL="https://github.com/davsar89/CADMesh.git"

log() {
    printf '[cadmesh-install] %s\n' "$*"
}

warn() {
    printf '[cadmesh-install] warning: %s\n' "$*" >&2
}

die() {
    printf '[cadmesh-install] error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [options]

Build and install CADMesh against the Geant4 10.7.4 install.

Options:
  --base-dir PATH         Directory containing the Geant4 install. Default: /geant4
  --jobs N               Number of parallel build jobs. Default: auto-detect.
  --dry-run              Validate inputs and print planned actions without building.
  --no-update-shell-rc   Do not modify ~/.bashrc.
  -h, --help             Show this help message.
EOF
}

absolute_path() {
    local path="$1"

    if [[ "$path" == "/" ]]; then
        printf '/\n'
    elif [[ "$path" == /* ]]; then
        printf '%s\n' "${path%/}"
    else
        printf '%s/%s\n' "$(pwd)" "${path%/}"
    fi
}

parse_args() {
    while (($#)); do
        case "$1" in
            --base-dir)
                shift
                [[ $# -gt 0 && -n "$1" ]] || die "--base-dir requires a path"
                BASE_DIR="$1"
                ;;
            --jobs)
                shift
                [[ $# -gt 0 && -n "$1" ]] || die "--jobs requires a positive integer"
                [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "--jobs requires a positive integer"
                JOBS="$1"
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --no-update-shell-rc)
                UPDATE_SHELL_RC=false
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
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
    BASE_DIR="$(absolute_path "$BASE_DIR")"
    [[ "$BASE_DIR" != "/" ]] || die "Refusing to use / as the base directory"

    GEANT4_INSTALL_DIR="${BASE_DIR}/geant4_install_${GEANT4_INTERNAL_VERSION}"
    GEANT4_ENV_FILE="${BASE_DIR}/geant4_10_7_env.sh"
    DEFAULT_GEANT4_CMAKE_DIR="${GEANT4_INSTALL_DIR}/lib/Geant4-${GEANT4_VERSION}"
    CMAKE_PATH="${BASE_DIR}/cmake/bin/cmake"

    CADMESH_SOURCE_DIR="${BASE_DIR}/CADMesh"
    CADMESH_BUILD_DIR="${BASE_DIR}/build_cadmesh_g4_${GEANT4_INTERNAL_VERSION}"
    CADMESH_INSTALL_DIR="${BASE_DIR}/install_cadmesh_g4_${GEANT4_INTERNAL_VERSION}"
    CADMESH_ENV_FILE="${BASE_DIR}/cadmesh_env.sh"
}

print_configuration() {
    cat <<EOF
[cadmesh-install] Configuration
  Base dir:      ${BASE_DIR}
  Geant4:        ${GEANT4_VERSION} (${GEANT4_INTERNAL_VERSION})
  Geant4 env:    ${GEANT4_ENV_FILE}
  CMake:         ${CMAKE_PATH}
  CADMesh repo:  ${CADMESH_REPO_URL}
  Source dir:    ${CADMESH_SOURCE_DIR}
  Build dir:     ${CADMESH_BUILD_DIR}
  Install dir:   ${CADMESH_INSTALL_DIR}
  Env file:      ${CADMESH_ENV_FILE}
  Jobs:          ${JOBS}
  Update bashrc: ${UPDATE_SHELL_RC}
EOF
}

print_dry_run_plan() {
    cat <<EOF
[cadmesh-install] Dry-run major actions
  1. Source Geant4 environment from ${GEANT4_ENV_FILE}.
  2. Locate Geant4Config.cmake under ${GEANT4_INSTALL_DIR}.
  3. Remove previous CADMesh source/build/install directories.
  4. Clone ${CADMESH_REPO_URL}.
  5. Configure, build, and install CADMesh.
  6. Write CADMesh environment file: ${CADMESH_ENV_FILE}
  7. Update ~/.bashrc: ${UPDATE_SHELL_RC}
EOF
}

ensure_inside_base() {
    local target="$1"

    case "$target" in
        "${BASE_DIR}/"*) ;;
        *) die "Refusing to remove path outside base directory: ${target}" ;;
    esac
}

remove_generated_path() {
    local target="$1"
    ensure_inside_base "$target"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would remove ${target}"
        return
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        rm -rf -- "$target"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

source_geant4_environment() {
    [[ -f "$GEANT4_ENV_FILE" ]] || die "Geant4 environment file not found: ${GEANT4_ENV_FILE}"
    # shellcheck source=/dev/null
    source "$GEANT4_ENV_FILE"
}

find_geant4_cmake_dir() {
    if [[ -f "${DEFAULT_GEANT4_CMAKE_DIR}/Geant4Config.cmake" ]]; then
        printf '%s\n' "$DEFAULT_GEANT4_CMAKE_DIR"
        return
    fi

    find "$GEANT4_INSTALL_DIR" -type f -name Geant4Config.cmake -printf '%h\n' -quit 2>/dev/null || true
}

check_prerequisites() {
    require_command git
    require_command make

    [[ -x "$CMAKE_PATH" ]] || die "CMake executable not found: ${CMAKE_PATH}"
    [[ -d "$GEANT4_INSTALL_DIR" ]] || die "Geant4 install directory not found: ${GEANT4_INSTALL_DIR}"

    source_geant4_environment
    GEANT4_CMAKE_DIR="$(find_geant4_cmake_dir)"
    [[ -n "$GEANT4_CMAKE_DIR" ]] || die "Geant4Config.cmake not found under ${GEANT4_INSTALL_DIR}"
}

write_cadmesh_environment() {
    log "Writing CADMesh environment file: ${CADMESH_ENV_FILE}"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would write ${CADMESH_ENV_FILE}"
        return
    fi

    cat >"$CADMESH_ENV_FILE" <<EOF
# Generated by installation_script_linux_only_CADmesh.bash
# shellcheck shell=bash

export cadmesh_DIR="${CADMESH_INSTALL_DIR}/lib/cmake/cadmesh-1.1.0"
export C_INCLUDE_PATH="\${C_INCLUDE_PATH:+\${C_INCLUDE_PATH}:}${CADMESH_INSTALL_DIR}/include"
export CPLUS_INCLUDE_PATH="\${CPLUS_INCLUDE_PATH:+\${CPLUS_INCLUDE_PATH}:}${CADMESH_INSTALL_DIR}/include"
export LIBRARY_PATH="\${LIBRARY_PATH:+\${LIBRARY_PATH}:}${CADMESH_INSTALL_DIR}/lib"
export LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:+\${LD_LIBRARY_PATH}:}${CADMESH_INSTALL_DIR}/lib"
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
    local start_marker="## --> Added by CADmesh installation script"
    local end_marker="## <-- Added by CADmesh installation script"

    log "Updating ${bashrc} with managed CADMesh environment block."

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would update ${bashrc} to source ${CADMESH_ENV_FILE}"
        return
    fi

    touch "$bashrc"
    remove_marker_block "$bashrc" "$start_marker" "$end_marker"

    {
        printf '\n%s\n' "$start_marker"
        printf 'source %q\n' "$CADMESH_ENV_FILE"
        printf '%s\n' "$end_marker"
    } >>"$bashrc"
}

build_cadmesh() {
    log "Installing CADMesh against Geant4 CMake dir: ${GEANT4_CMAKE_DIR}"

    if [[ "$DRY_RUN" == true ]]; then
        return
    fi

    mkdir -p "$BASE_DIR"
    remove_generated_path "$CADMESH_SOURCE_DIR"
    remove_generated_path "$CADMESH_BUILD_DIR"
    remove_generated_path "$CADMESH_INSTALL_DIR"
    mkdir -p "$CADMESH_BUILD_DIR" "$CADMESH_INSTALL_DIR"

    git clone --depth 1 "$CADMESH_REPO_URL" "$CADMESH_SOURCE_DIR"

    (
        cd "$CADMESH_BUILD_DIR"
        "$CMAKE_PATH" \
            -DCMAKE_INSTALL_PREFIX="${CADMESH_INSTALL_DIR}" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_LIBDIR=lib \
            -DGeant4_DIR="${GEANT4_CMAKE_DIR}" \
            "$CADMESH_SOURCE_DIR"
        env G4VERBOSE=1 make -j"${JOBS}"
        make install
    )
}

main() {
    parse_args "$@"
    detect_jobs
    configure_paths
    print_configuration
    check_prerequisites

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run_plan
        log "Dry run complete."
        return
    fi

    build_cadmesh
    write_cadmesh_environment
    update_shell_rc
    log "Done."
}

main "$@"

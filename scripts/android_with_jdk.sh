#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

candidates=()
candidates+=("$ROOT_DIR/.tools/jdk-21")
if [[ -n "${RADIOMIX_JAVA_HOME:-}" ]]; then
  candidates+=("$RADIOMIX_JAVA_HOME")
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  candidates+=("$JAVA_HOME")
fi
candidates+=(
  "/usr/lib/jvm/java-21-openjdk"
  "/usr/lib/jvm/java-21-openjdk-amd64"
  "/usr/lib/jvm/temurin-21-jdk"
  "/usr/lib/jvm/java-17-openjdk"
  "/usr/lib/jvm/java-17-openjdk-amd64"
  "/usr/lib/jvm/temurin-17-jdk"
)

choose_java_home() {
  local candidate version major
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate/bin/java" ]] || continue
    version="$($candidate/bin/java -version 2>&1 | head -n1 | sed -E 's/.*version "([0-9]+).*/\1/')"
    if [[ "$version" == "17" || "$version" == "21" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

JAVA_HOME_SELECTED="$(choose_java_home || true)"
if [[ -z "$JAVA_HOME_SELECTED" ]]; then
  echo "No se encontro un JDK 17/21 utilizable. Define RADIOMIX_JAVA_HOME o JAVA_HOME." >&2
  exit 1
fi

export JAVA_HOME="$JAVA_HOME_SELECTED"
export PATH="$JAVA_HOME/bin:$PATH"

echo "Usando JAVA_HOME=$JAVA_HOME" >&2

if [[ $# -eq 0 ]]; then
  cd "$ROOT_DIR/android"
  exec ./gradlew tasks
fi

if [[ "$(basename "$1")" == "gradlew" || "$1" == "./gradlew" ]]; then
  cd "$ROOT_DIR/android"
  exec ./gradlew "${@:2}"
fi

cd "$ROOT_DIR"
exec "$@"

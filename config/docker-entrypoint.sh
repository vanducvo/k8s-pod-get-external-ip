#!/bin/sh
# vim:sw=4:ts=4:et

set -e

# Inject to wait service have public ip
apt update && apt install -y curl jq

auth_k8s_config_path="/var/run/secrets/kubernetes.io/serviceaccount"

get_k8s_service() {
  api_server="https://kubernetes.default.svc"
  service_name="$1"
  path="$2"
  token=$(cat "$path/token")
  ca="$path/ca.crt"
  namespace=$(cat "$path/namespace")

  data=$(curl --cacert "$ca" \
    --header "Authorization: Bearer $token" \
    -X GET "$api_server/api/v1/namespaces/$namespace/services/$service_name/" 2>/dev/null)

  echo "$data" | tr '\r\n' ' '
}

is_issue_external_ip() {
  if [ "null" = "$(printf "%s" "$1" | jq -r '.status | .loadBalancer | .ingress')" ]; then
    echo "false"
  else
    echo "true"
  fi
}

extract_ip(){
  printf "%s" "$1" | jq -r '.status | .loadBalancer | .ingress | .[] | .ip'
}

data="$(get_k8s_service $SERVICE_NAME $auth_k8s_config_path)"

while [ "false" = "$(is_issue_external_ip "$data")" ]; do
  echo "Waiting 10 for LoadBalancer issue external ip..."
  sleep 10
  data="$(get_k8s_service $SERVICE_NAME $auth_k8s_config_path)"
done

PUBLIC_IP="$(extract_ip "$data")"
export PUBLIC_IP

echo "PUBLIC_IP=$PUBLIC_IP"

if [ -z "${NGINX_ENTRYPOINT_QUIET_LOGS:-}" ]; then
  exec 3>&1
else
  exec 3>/dev/null
fi

if [ "$1" = "nginx" -o "$1" = "nginx-debug" ]; then
  if /usr/bin/find "/docker-entrypoint.d/" -mindepth 1 -maxdepth 1 -type f -print -quit 2>/dev/null | read v; then
    echo >&3 "$0: /docker-entrypoint.d/ is not empty, will attempt to perform configuration"

    echo >&3 "$0: Looking for shell scripts in /docker-entrypoint.d/"
    find "/docker-entrypoint.d/" -follow -type f -print | sort -V | while read -r f; do
      case "$f" in
      *.sh)
        if [ -x "$f" ]; then
          echo >&3 "$0: Launching $f"
          "$f"
        else
          # warn on shell scripts without exec bit
          echo >&3 "$0: Ignoring $f, not executable"
        fi
        ;;
      *) echo >&3 "$0: Ignoring $f" ;;
      esac
    done

    echo >&3 "$0: Configuration complete; ready for start up"
  else
    echo >&3 "$0: No files found in /docker-entrypoint.d/, skipping configuration"
  fi
fi

exec "$@"

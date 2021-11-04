# K8s Pod Get External IP With Bash Shell
### Mechanic to get External IP of Load Balancer from Pod
Sometimes, we want to get External IP of service type `Loabancer` in K8s
My approach base [Accessing the API from a Pod ](https://kubernetes.io/docs/tasks/access-application-cluster/access-cluster/#accessing-the-api-from-a-pod) 
>When accessing the API from a pod, locating and authenticating to the apiserver are somewhat different.
>
>The recommended way to locate the apiserver within the pod is with `the kubernetes.default.svc` DNS name, which resolves to a Service IP which in turn will be routed to an apiserver.
>
> The recommended way to authenticate to the apiserver is with a service account credential. By kube-system, a pod is associated with a service account, and a credential (token) for that service account is placed into the filesystem tree of each container in that pod, at `/var/run/secrets/kubernetes.io/serviceaccount/token`.

I will present approach with step-by-step example with [Kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/)

**Example problem**: Wait to `service` have `external` ip before start `nginx`
In this project I inspect `service` by `service name`. Assumption, pod know `service_name` by pass `SERVICE_NAME` over container.
#### Step 1: Create [Service Account](./service-account.yaml)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: service-reader
  namespace: default
```

#### Step 2: Create [Cluster Role](./cluster-role.yaml)
Create role allow access service with readonly
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: inspect-services
  namespace: defaults
rules:
  - apiGroups:
      - "" # "" indicates the core API group
    resources:
      - services
    verbs:
      - get
      - watch
      - list
```
#### Step 3: [Binding](./binding-role.yaml) `Cluster Role ` with `ServiceAccount`
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: service-reader-with-role-inspect-services
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: inspect-services
subjects:
  - kind: ServiceAccount
    name: service-reader
    namespace: default
```

#### Step 4: Set `serviceAccountName` to [Deployment](./deployment.yaml)
```yaml
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: nginx
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nginx
    spec:
      # Must be set
      serviceAccountName: service-reader
      containers:
        - name: nginx
```

#### Step 5: Inject Code Get External IP When Pod Start
Overide `docker-entrypoint.sh` of `ngix` docker. See detail in [here](./deployment.yaml)
```shell
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
```

#### Result:
Inspect by `kubectl`
```shell
> k get services       
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)        AGE
kubernetes      ClusterIP      10.96.0.1       <none>          443/TCP        22m
nginx-service   LoadBalancer   10.106.50.213   10.106.50.213   80:32383/TCP   6m27s

```
Nginx Log:
```shell
Setting up libjq1:amd64 (1.5+dfsg-2+b1) ...
Setting up jq (1.5+dfsg-2+b1) ...
Processing triggers for libc-bin (2.28-10) ...
Waiting 10 for LoadBalancer issue external ip...
Waiting 10 for LoadBalancer issue external ip...
Waiting 10 for LoadBalancer issue external ip...
Waiting 10 for LoadBalancer issue external ip...
Waiting 10 for LoadBalancer issue external ip...
PUBLIC_IP=10.106.50.213
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
```

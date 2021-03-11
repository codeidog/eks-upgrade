### Stage 1: Create the cluster
  #### Steps:
  1. ```
     eksctl create cluster \
      --name ido-cluster \
      --zones eu-west-2b,eu-west-2c \
      --version 1.15 \
      --with-oidc \
      --ssh-access \
      --ssh-public-key ido \
      --managed \
      --nodegroup-name ido-ng \
      --instance-types t2.medium
      ```
### Stage 2: Deploy Redis database
  #### Steps:
  1. helm repo add bitnami https://charts.bitnami.com/bitnami
  2. helm install -n redis --create-namespace my-redis bitnami/redis
  3. Get the redis password export  
  ```REDIS_PASSWORD=$(kubectl get secret --namespace redis my-redis -o jsonpath="{.data.redis-password}" | base64 --decode)```
  4. Port forward localhost to the cluster svc  
  ```kubectl port-forward --namespace redis svc/my-redis-master 6379:6379```
  5. Connect to the redis db  
  ```redis-cli -h 127.0.0.1 -p 6379 -a $REDIS_PASSWORD```
  6. Create a new key value pair  
  ``` set <key> <value> ```
  7. Get the keys created  
  ``` keys *```  
### Stage 3: Deploy Nginx ingress controller
  #### Steps:
  1. helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
  2. helm install --create-namespace -n ingress --version 2.9.1  ingress-nginx ingress-nginx/ingress-nginx


### Stage 4: Deploy test-nginx application
  #### Steps:
  1. helm install --create-namespace -n nginx-test nginx-test nginx-test


### Stage 5: Deploy hello-world application
  #### Steps:
  1. helm install --create-namespace -n hello-world hello-world hello-world

### Stage 4: Check cluster upgrade prerequisites (https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html#1-16-prequisites)

#### Steps: 
  1. Verify that the proper pod security policies are in place  
  ```kubectl get psp eks.privileged```  
  If there were any issues see [default pod security policy](https://docs.aws.amazon.com/eks/latest/userguide/pod-security-policy.html#default-psp)
  before proceeding  
  **Sample output:**  
  ```
  NAME             PRIV   CAPS   SELINUX    RUNASUSER   FSGROUP    SUPGROUP   READONLYROOTFS   VOLUMES
eks.privileged   true   *      RunAsAny   RunAsAny    RunAsAny   RunAsAny   false            *
```
  2. From cluster versions 1.17 or earlier we need to remove a discontinued term for the CoreDNS manifest
    a. Check to see of the manifest has a line that only has the word ```upstream```  
    `kubectl get configmap coredns -n kube-system -o jsonpath='{$.data.Corefile}' | grep upstream
  `   
  b. If it does, execute the following command and remove the line with that value:  
  `kubectl edit configmap coredns -n kube-system -o yaml`  

  3. Update api version for the following resources:  
  **Deployment** - apps/v1  
  **DaemonSet** - apps/v1  
  **StatefulSet** - apps/v1  
  **ReplicaSet** - apps/v1  
  **PodSecurityPolicy** - policy/v1beta1  
  **NetworkPolicy** - networking.k8s.io/v1  
  Get all the resources versions:  
  `kubectl get all -A -o custom-columns=NAME:.metadata.name,KIND:.kind,API_VERSION:.apiVersion`


### Stage 5: Upgrade the Cluster
**Note: Since EKS runs a highly available cluster it is only possible to upgrade from one minor version at a time**

#### Upgrade using eksctl:
  **Upgrade the control plane**
  1. Execute the following command to make sure you everything is up to date before the upgrade:  
  `eksctl upgrade cluster --name=<cluster-name> --version=<to-version`  
  **Sample output**
  ```
  2021-03-10 15:30:11 [ℹ]  eksctl version 0.40.0
2021-03-10 15:30:11 [ℹ]  using region eu-west-2
2021-03-10 15:30:13 [ℹ]  (plan) would upgrade cluster "ido-cluster" control plane from current version "1.16" to "1.17"
2021-03-10 15:30:14 [ℹ]  re-building cluster stack "eksctl-ido-cluster-cluster"
2021-03-10 15:30:14 [✔]  all resources in cluster stack "eksctl-ido-cluster-cluster" are up-to-date
2021-03-10 15:30:14 [ℹ]  checking security group configuration for all nodegroups
2021-03-10 15:30:14 [ℹ]  all nodegroups have up-to-date configuration
2021-03-10 15:30:14 [!]  no changes were applied, run again with '--approve' to apply the changes
```
  2. Execute the same with --approve to start the upgrade process  
  `eksctl upgrade cluster --name=<cluster-name> --version=<to-version --aprove`

  3. Patch the Kube-Proxy `DaemonSet`  

| Kubernetes version      | 1.19 | 1.18 | 1.17 | 1.16 | 1.15|
| :-----------: | :-----------: | :-----------: | :-----------: | :-----------: | :-----------: |
| *KubeProxy*      | 1.19.6       | 1.18.8       | 1.17.9       | 1.16.13       | 1.15.11       |  

  a. Retrieve the currnet version of the Kube-Proxy  
  ```bash
  kubectl get daemonset kube-proxy --namespace kube-system -o=jsonpath='{$.spec.template.spec.containers[:1].image}'
  ```  
  **Example Output:**  
  <pre>
<b>602401143452</b>.dkr.ecr.<b>eu-west-2</b>.amazonaws.com/eks/kube-proxy:v<b>1.16.13</b>-eksbuild.1
</pre>  
  b. Update the kube proxy image by replacing `602401143452` and `eu-west-2` with the result from your output and `1.16.13` 
with the supported version by your cluster  

If you're deploying a version that is earlier than `1.19.6`, then replace `eksbuild.2` with `eksbuild.1`. 
<pre>
kubectl set image daemonset.apps/kube-proxy \
  -n kube-system \
  kube-proxy=<b>602401143452</b>.dkr.ecr.<b>us-west-2</b>.amazonaws.com/eks/kube-proxy:v<b>1.19.6</b>-eksbuild.2
</pre>

  4. Patch the CoreDNS `deployment` image  

| Kubernetes version      | 1.19 | 1.18 | 1.17 | 1.16 | 1.15|
| :-----------: | :-----------: | :-----------: | :-----------: | :-----------: | :-----------: |
| *CoreDNS*      | 1.8.0       | 1.7.0       | 1.6.6       | 1.6.6       | 1.6.6       |      

  a. If your current coredns version is 1.5.0 or later, but earlier than the recommended version, then skip this step. If your current version is earlier than 1.5.0, then you need to modify the config map for coredns to use the forward plug-in, rather than the proxy plug-in.  
***Open the configmap with the following command.***

```bash
kubectl edit configmap coredns -n kube-system
```

Replace proxy in the following line with `forward`. Save the file and exit the editor.

```
proxy . /etc/resolv.conf
```
  b. Retrieve your coreDNS version
  ```bash
  kubectl get deployment coredns --namespace kube-system -o=jsonpath='{$.spec.template.spec.containers[:1].image}'
  ``` 
  **Example Output:**  
  <pre>
<b>602401143452</b>.dkr.ecr.<b>eu-west-2</b>.amazonaws.com/eks/coredns:v<b>1.6.6</b>-eksbuild.1
</pre>
c. Update the CoreDNS image by replacing `602401143452` and `eu-west-2` with the result from your output and `1.6.6` 
with the supported version by your cluster  

<pre>
kubectl set image daemonset.apps/kube-proxy \
  -n kube-system \
  kube-proxy=<b>602401143452</b>.dkr.ecr.<b>eu-west-2</b>.amazonaws.com/eks/coredns:v<b>1.7.0</b>-eksbuild.1
</pre>  

  5. Upgrade the nodegroup
  a. Get your cluster name by running following command:  
  ```
  eksctl get cluster
  ```
  **Example output:**  
  ```
  021-03-11 17:37:13 [ℹ]  eksctl version 0.40.0
2021-03-11 17:37:13 [ℹ]  using region eu-west-2
NAME		REGION		EKSCTL CREATED
ido-cluster	eu-west-2	True
```
  b. Get your nodegroup name by running the following command:
  ```bash
  eksctl get nodegroup --cluster=<cluster_name>
  ```
  c. Perform the upgrade to the node group by running the following command:
  ```bash
  eksctl upgrade nodegroup \
   --cluster=<cluster_name> \
   --name=<nodegroup_name> \
   --kubernetes-version=<to_version>
   ```
This command will spin a new node group with the required version and perform a rolling update by making the nodes with the old version unscheduleable.
### Issues I have encountered:
  1. ***issue:*** When executing the upgrade from the aws console the nodes might not be scheduled on the same AZ, casuing STS to not be able to access their volume  
  ***resolution:*** create a new node group specifying the required AZ like so  
  ```
  eksctl create nodegroup \ 
  --name ng_name \ 
  --cluster cluster_name \ 
  --ssh-access  \ 
  --ssh-public-key key_name \ 
  --node-zones=AZ_1,AZ_2
  ```
  After the creation has been completed successfully verify that all the pods are in a running state and execute the following command to delete the old node group:
  ```
  eksctl delete nodegroup --cluster=<cluster_name> --name=<old_nodegroup_name>
  ```
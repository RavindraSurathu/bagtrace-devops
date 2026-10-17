# BagTrace deployment guide

This guide walks through every way to deploy BagTrace, one step at a time, and shows what you should see at each stage. Start with **Part 1 (Docker Compose)**: it runs on your laptop in five minutes and shows what the finished app looks like. Then move to the AWS methods.

| Part | Method | Where it runs | Time | Cost |
|------|--------|--------------|------|------|
| 1 | Docker Compose | Your laptop | 5 min | Free |
| 2 | Shell scripts | 3 EC2 servers | 30 min | Small (stop or delete the servers afterwards) |
| 3 | Ansible | 3 EC2 servers | 20 min | Small |
| 4 | Terraform | Full AWS environment | 15 min | Several US$ per day while running |
| 5 | Kubernetes | minikube on your laptop, or EKS | 15 to 40 min | Free on minikube; EKS is billed hourly |

Every part ends with the same check, **[Verify the deployment](#verify-the-deployment)**, and the same **[Expected result](#expected-result)**.

---

## Before you start

### Tools

Install only what the part you're doing needs:

| Tool | Needed for | Check |
|------|-----------|-------|
| Git | All parts | `git --version` |
| Docker Desktop (or Docker Engine + Compose) | Parts 1 and 5 | `docker compose version` |
| AWS CLI v2 | Parts 2 to 5 (AWS) | `aws --version` |
| Terraform 1.5 or newer | Part 4 | `terraform -version` |
| Ansible (ansible-core 2.15 or newer) | Part 3 | `ansible --version` |
| kubectl, plus minikube or eksctl | Part 5 | `kubectl version --client` |

### AWS account setup (Parts 2 to 5)

1. Create an IAM user for yourself (not the root user), give it the **AdministratorAccess** policy for this lab, and create an access key.
2. Configure the CLI and confirm it works:
   ```bash
   aws configure            # paste the access key, secret, region (e.g. ap-south-1), output json
   aws sts get-caller-identity
   ```
   You should see your account number and user ARN.
3. Create an SSH key pair in the same region and protect the file:
   ```bash
   aws ec2 create-key-pair --key-name bagtrace-key --query KeyMaterial --output text > bagtrace-key.pem
   chmod 400 bagtrace-key.pem
   ```
4. Find your public IP (Terraform and the security group rules use it):
   ```bash
   curl -s https://checkip.amazonaws.com
   ```

### Get the code

```bash
git clone https://github.com/RavindraSurathu/bagtrace-devops.git
cd bagtrace-devops
```

---

## Part 1 · Docker Compose (local)

1. **Start Docker Desktop** and wait until it reports it is running.
2. **Build and start the three containers** from the repo root:
   ```bash
   docker compose up -d --build
   ```
   The first run downloads MySQL and Python images, so it takes a few minutes.
3. **Watch the containers become healthy:**
   ```bash
   docker compose ps
   ```
   Wait until `mysql` shows `healthy`, and `backend` and `frontend` show `running`. MySQL loads the schema and six sample bags on its first start, which takes about 30 seconds.
4. **Check the API through Nginx:**
   ```bash
   curl http://localhost:8080/health
   ```
   Expected: `{"database":"up","status":"ok"}`
5. **Open the dashboard:** http://localhost:8080. Continue with **[Verify the deployment](#verify-the-deployment)**.
6. **Read the logs** if something looks wrong:
   ```bash
   docker compose logs -f backend
   ```
7. **Clean up** when finished. `-v` also deletes the database volume:
   ```bash
   docker compose down -v
   ```

---

## Lab servers for Parts 2 and 3

Parts 2 and 3 install BagTrace on three plain servers, one per tier. Create them once and reuse them.

1. **Create a security group** named `bagtrace-lab` in your default VPC (EC2 → Security Groups → Create) with these inbound rules:

   | Type | Port | Source | Why |
   |------|------|--------|-----|
   | SSH | 22 | My IP | You connect to all three servers |
   | HTTP | 80 | Anywhere (0.0.0.0/0) | Browser access to the frontend |
   | Custom TCP | 8080 | `bagtrace-lab` (the group itself) | Frontend → backend |
   | MySQL/Aurora | 3306 | `bagtrace-lab` (the group itself) | Backend → MySQL |

2. **Launch three instances** (EC2 → Launch instances):
   - Names: `bagtrace-mysql`, `bagtrace-backend`, `bagtrace-frontend`
   - AMI: **Red Hat Enterprise Linux 9** (or your course's RHEL 9 practice AMI)
   - Type: `t3.micro` (use `t3.small` for MySQL if it runs out of memory)
   - Key pair: `bagtrace-key`; security group: `bagtrace-lab`; public IP: enabled
3. **Write down** each server's **public IP** (to SSH in) and **private IP** (for the tiers to talk to each other).

> If you have a Route 53 domain, `shell/launch-instances.sh` creates the three servers and DNS records for you:
> `AMI_ID=ami-... SG_ID=sg-... ZONE_ID=Z... DOMAIN=example.com ./shell/launch-instances.sh mysql backend frontend`

---

## Part 2 · Shell scripts

Run these in order: MySQL first, then backend, then frontend. Each tier needs the one behind it.

### Step 1: MySQL server

```bash
ssh -i bagtrace-key.pem ec2-user@<mysql-public-ip>
sudo dnf install -y git
git clone https://github.com/RavindraSurathu/bagtrace-devops.git && cd bagtrace-devops
sudo MYSQL_ROOT_PASSWORD='Root@Pass123' DB_PASSWORD='App@Pass123' ./shell/01-mysql.sh
```

Expected output: a series of green `SUCCESS` lines, ending with `01-mysql finished in N seconds`.

Check it:

```bash
mysql -ubagtrace -p'App@Pass123' -h 127.0.0.1 -e "SELECT tag, flight, status FROM bagtrace.bags;"
```

You should see six sample bags.

### Step 2: Backend server

```bash
ssh -i bagtrace-key.pem ec2-user@<backend-public-ip>
sudo dnf install -y git
git clone https://github.com/RavindraSurathu/bagtrace-devops.git && cd bagtrace-devops
sudo DB_HOST=<mysql-private-ip> DB_PASSWORD='App@Pass123' ./shell/02-backend.sh
```

Check it:

```bash
curl http://127.0.0.1:8080/health          # {"database":"up","status":"ok"}
systemctl status bagtrace-backend          # active (running)
```

### Step 3: Frontend server

```bash
ssh -i bagtrace-key.pem ec2-user@<frontend-public-ip>
sudo dnf install -y git
git clone https://github.com/RavindraSurathu/bagtrace-devops.git && cd bagtrace-devops
sudo BACKEND_HOST=<backend-private-ip> ./shell/03-frontend.sh
```

Check it:

```bash
curl http://127.0.0.1/health               # same JSON, now served through Nginx
```

### Step 4: Open the app

Browse to `http://<frontend-public-ip>` and continue with **[Verify the deployment](#verify-the-deployment)**.

**How the scripts behave:** every step is checked by `VALIDATE`, and the script stops at the first failure. Full logs are in `/var/log/bagtrace/<script>.log` on each server, and running a script again is safe.

---

## Part 3 · Ansible

Ansible does Part 2's work from your laptop in one command. Use fresh lab servers, or the same ones from Part 2 with the **same passwords** you used there (the roles are idempotent).

1. **Install Ansible and the collections** the roles use:
   ```bash
   pip install ansible-core
   cd ansible
   ansible-galaxy collection install -r requirements.yml
   ```
2. **Edit `inventory.ini`** to use the **public** IPs, which Ansible connects to:
   ```ini
   [mysql]
   13.233.10.11

   [backend]
   13.233.10.12

   [frontend]
   13.233.10.13
   ```
3. **Edit `group_vars/all/main.yml`** to use the **private** IPs, which the servers use to talk to each other:
   ```yaml
   db_host: 172.31.5.20
   backend_host: 172.31.5.21
   ```
4. **Create the encrypted secrets file:**
   ```bash
   cp group_vars/all/vault.example.yml group_vars/all/vault.yml
   vi group_vars/all/vault.yml           # set both passwords
   ansible-vault encrypt group_vars/all/vault.yml
   ```
   `vault.yml` is git-ignored, so it never reaches GitHub.
5. **Test connectivity:**
   ```bash
   ansible all -m ping --private-key ../bagtrace-key.pem
   ```
   Every host should answer `"ping": "pong"`.
6. **Run the playbook:**
   ```bash
   ansible-playbook site.yml --ask-vault-pass --private-key ../bagtrace-key.pem
   ```
   Expected: the play recap shows `failed=0` for all three hosts. Run it a second time and most tasks report `ok` instead of `changed`, which shows the roles are idempotent.
7. **Open** `http://<frontend-public-ip>` and continue with **[Verify the deployment](#verify-the-deployment)**.

Tip: to redeploy one tier only, add `--limit backend` (or `mysql` or `frontend`).

---

## Part 4 · Terraform (full AWS environment)

Terraform builds everything in Parts 2 and 3 itself: a new VPC, subnets, NAT gateway, security groups, a bastion, the three servers and a load balancer. Each server clones this repo at boot and runs its `shell/` script, so you don't SSH in to install anything.

1. **Create your variables file:**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```
   Set `key_name = "bagtrace-key"` and `admin_cidr = "<your-ip>/32"`, and pick a `region`.
2. **Initialise** (downloads the AWS provider):
   ```bash
   terraform init
   ```
3. **Preview the changes:**
   ```bash
   terraform plan
   ```
   Expected: `Plan: 46 to add, 0 to change, 0 to destroy`. Read the list: VPC, subnets, route tables, NAT, security groups and rules, four instances (bastion, mysql, backend, frontend), two generated passwords, and the ALB pieces.
4. **Create the environment:**
   ```bash
   terraform apply          # type 'yes'
   ```
   This takes about 3 to 5 minutes. Then print the outputs:
   ```bash
   terraform output
   ```
   You'll see `app_url`, `bastion_public_ip` and `private_ips`.
5. **Wait for the servers to finish bootstrapping**, about 5 more minutes. In the AWS console, go to EC2 → Target Groups → `bagtrace-dev-frontend` → Targets. Once the frontend shows **healthy**, the app is live.
6. **Open** the `app_url` value (`http://bagtrace-dev-alb-....elb.amazonaws.com`) and continue with **[Verify the deployment](#verify-the-deployment)**.
7. **Look inside a server** through the bastion. The tiers are in private subnets, so you jump through the bastion:
   ```bash
   ssh-add bagtrace-key.pem
   ssh -J ec2-user@<bastion_public_ip> ec2-user@<backend-private-ip>
   sudo tail -f /var/log/bagtrace-bootstrap.log     # what user_data did at boot
   sudo cat /var/log/bagtrace/02-backend.log
   ```
8. **Destroy everything** when you're done. This matters: the NAT gateway, ALB and RHEL instances are billed every hour.
   ```bash
   terraform destroy        # type 'yes'
   ```

**Security notes worth mentioning in interviews:**
- Only the ALB and bastion are public. The frontend and backend sit in private subnets, and MySQL sits in an isolated database subnet.
- Each security group allows traffic only from the tier in front of it: internet → ALB:80 → frontend:80 → backend:8080 → mysql:3306.
- Passwords are generated by Terraform and passed through user_data. In production I'd use AWS Secrets Manager instead.

---

## Part 5 · Kubernetes

### Step 0: make the container images public (one time)

The GitHub Actions pipeline pushes `bagtrace-backend` and `bagtrace-frontend` to GitHub Container Registry, and new packages start out **private**. On GitHub, go to your profile → **Packages** → `bagtrace-backend` → **Package settings** → **Change visibility** → **Public**. Repeat for `bagtrace-frontend`. Without this, pods fail with `ImagePullBackOff`.

### Option A: minikube (local, free)

1. **Start a cluster:**
   ```bash
   minikube start --cpus 2 --memory 4g
   ```
2. **Deploy everything.** Kustomize also builds the MySQL schema ConfigMap:
   ```bash
   kubectl apply -k k8s/
   ```
3. **Watch the pods start:**
   ```bash
   kubectl -n bagtrace get pods -w
   ```
   Expected after 1 to 2 minutes: `mysql-0` is `1/1 Running`, plus two `backend-…` and two `frontend-…` pods, all `Running`. The backend pods only become Ready once MySQL is up, because their readiness probe checks the database.
4. **Reach the app:**
   ```bash
   kubectl -n bagtrace port-forward svc/frontend 8080:80
   ```
   Open http://localhost:8080 and continue with **[Verify the deployment](#verify-the-deployment)**.
5. **Explore what Kubernetes is doing:**
   ```bash
   kubectl -n bagtrace get all,pvc,ingress,networkpolicy
   kubectl -n bagtrace logs deploy/backend
   kubectl -n bagtrace delete pod -l app=backend     # watch new pods replace them (self-healing)
   ```
   For the autoscaler to work, run `minikube addons enable metrics-server`, then check `kubectl -n bagtrace get hpa`.
6. **Clean up:**
   ```bash
   kubectl delete -k k8s/ && minikube stop
   ```

### Option B: Amazon EKS

1. **Create a cluster** (about 15 to 20 minutes):
   ```bash
   eksctl create cluster --name bagtrace --region ap-south-1 --nodes 2 --node-type t3.medium
   ```
2. **Add the EBS storage driver** so the MySQL volume can be created:
   ```bash
   eksctl utils associate-iam-oidc-provider --cluster bagtrace --approve
   eksctl create iamserviceaccount --cluster bagtrace --namespace kube-system --name ebs-csi-controller-sa \
     --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy --approve --role-only \
     --role-name bagtrace-ebs-csi
   eksctl create addon --cluster bagtrace --name aws-ebs-csi-driver \
     --service-account-role-arn arn:aws:iam::<account-id>:role/bagtrace-ebs-csi
   ```
   If `kubectl get storageclass` shows no `(default)` class, mark gp2 as default:
   `kubectl patch storageclass gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'`
3. **Deploy:** `kubectl apply -k k8s/`
4. **Expose the app.** The quickest way is a LoadBalancer Service:
   ```bash
   kubectl -n bagtrace patch svc frontend -p '{"spec":{"type":"LoadBalancer"}}'
   kubectl -n bagtrace get svc frontend      # wait for EXTERNAL-IP, then open it
   ```
   For the Ingress in `k8s/30-frontend.yaml`, install the [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) first; it then creates an ALB for you.
5. **Delete the cluster** when finished: `eksctl delete cluster --name bagtrace --region ap-south-1`

---

## Verify the deployment

Do this after any part. Replace `$APP` with your address: `http://localhost:8080`, `http://<frontend-ip>`, or the Terraform `app_url`.

1. **Health:**
   ```bash
   curl $APP/health
   ```
   Expected: `{"database":"up","status":"ok"}`. If the database is down, you get `"degraded"` with HTTP 503.
2. **Dashboard:** open `$APP` in a browser.
   - The top-right indicator is green: *API up · database up*.
   - The tiles show counts by status, and the table lists six sample bags (QF401, EK525, AI101, NZ102).
3. **Check in a new bag:** in **Send a BSM**, keep the sample message and click **Process message**.
   - Expected: *Accepted 2 bag(s) on EK525 HYD → DXB*.
   - Two new rows appear for tags `0176543300` and `0176543301`, each 20 kg (41 kg split across 2 pieces) with status *Checked in*.
4. **Move a bag along:** change one bag's status dropdown to **Loaded**. The pill turns green and the tiles update.
5. **Track it:** type `0176543300` in **Track a bag**. You see the current status and its history: `BSM_ADD`, then `LOADED`.
6. **Send a DELBSM:** add a line `DEL` after `BSM` in the message box and process it again. Both bags turn red: *Deleted*.
7. **Try a bad message:** replace the text with `hello` and click Process. Expected: a red error, *Message must start with a 'BSM' line*.
8. **Use the API directly:**
   ```bash
   curl "$APP/api/bags?flight=EK525"
   curl $APP/api/stats
   curl -X PATCH $APP/api/bags/0081123456 -H 'Content-Type: application/json' -d '{"status":"ARRIVED"}'
   printf 'BSM\n.V/1LBLR\n.F/6E201/19OCT/DEL/Y\n.N/0222000111001\n.W/K/1/15\n.P/1SINGH/RAJ\nENDBSM' \
     | curl -X POST $APP/api/bsm -H 'Content-Type: text/plain' --data-binary @-
   ```
9. **Metrics:** the API exposes Prometheus counters such as `bagtrace_bsm_messages_total` on port 8080, which isn't public. Read them from inside each environment:
   - Docker: `docker compose exec frontend wget -qO- http://backend:8080/metrics`
   - Servers: on the backend server, `curl http://127.0.0.1:8080/metrics`
   - Kubernetes: `kubectl -n bagtrace port-forward svc/backend 8081:8080`, then `curl http://localhost:8081/metrics`

## Expected result

When everything works:

- One URL serves the **BagTrace dashboard**. The browser only ever talks to **Nginx (web tier)**.
- Nginx forwards `/api/*` and `/health` to the **Python API (app tier)** on port 8080.
- The API is the only component that talks to **MySQL (DB tier)** on port 3306. The frontend cannot reach the database directly, and the security groups, Docker networks and NetworkPolicies all enforce this.
- Bags persist across restarts: restart the backend (`systemctl restart bagtrace-backend`, `docker compose restart backend`, or delete a backend pod) and the data is still there.

```text
Browser ──▶ Nginx :80 ──/api──▶ Python API :8080 ──▶ MySQL :3306
           (web tier)          (app tier)            (db tier)
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Dashboard loads but shows *API or database unreachable* | Backend down, or wrong `BACKEND_HOST` | On the frontend: `curl http://<backend-ip>:8080/health/live`. Check the 8080 security group rule. |
| `/health` returns `"database":"down"` | Backend can't reach MySQL | From the backend: `timeout 2 bash -c '</dev/tcp/<mysql-ip>/3306' && echo open`. Check the 3306 rule and `DB_HOST` in `/etc/bagtrace.env`. |
| 502 Bad Gateway from Nginx on RHEL | SELinux blocks Nginx's outbound connections | `sudo setsebool -P httpd_can_network_connect 1` (the frontend script and role already do this) |
| `01-mysql.sh` fails at *Setting MySQL root password* | Password already set to a different value | Rerun with the same `MYSQL_ROOT_PASSWORD` you used first |
| Backend fails to start | Bad dependency install or env file | `sudo journalctl -u bagtrace-backend -n 50` |
| Terraform target stays *unhealthy* | Bootstrap still running or failed | SSH through the bastion and read `/var/log/bagtrace-bootstrap.log` |
| `terraform apply`: *InvalidKeyPair.NotFound* | Key pair in a different region | Create the key pair in the same region as `region` in tfvars |
| Pods stuck in `ImagePullBackOff` | GHCR packages are private | Make both packages public (Part 5, Step 0) |
| `mysql-0` stuck in `Pending` | No storage class or EBS driver | minikube: `minikube addons enable storage-provisioner`. EKS: Part 5B, Step 2. |
| Backend pods `Running` but not `Ready` | MySQL still initialising | Wait 1 to 2 minutes; check `kubectl -n bagtrace logs mysql-0` |
| `docker compose up` port error | Port 8080 already in use | Change `"8080:80"` to `"8081:80"` in `docker-compose.yml` |

## Clean-up checklist

- [ ] Docker: `docker compose down -v`
- [ ] Lab servers (Parts 2 and 3): terminate the three instances and delete the `bagtrace-lab` security group
- [ ] Terraform: `terraform destroy`
- [ ] minikube: `kubectl delete -k k8s/ && minikube stop`
- [ ] EKS: `eksctl delete cluster --name bagtrace --region ap-south-1`
- [ ] Billing: check AWS Billing → Bills the next day to confirm nothing is still running

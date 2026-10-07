# Automated Infrastructure & Deployment: Terraform, Ansible, Jenkins on AWS

This project automates infrastructure creation and application deployment on AWS.

- **Terraform** creates the VPC, subnet, security group, 3 EC2 instances and 3 Elastic IPs.
- **Ansible** (installed on the master) installs Apache2 on one agent and Nginx on the other.
- **Jenkins** (installed on the master) runs the Ansible playbook as a job.
- **GitHub webhook** triggers the Jenkins job on every push to the repository.

## Architecture

| Component | Details |
|---|---|
| Region | us-east-1 (N. Virginia) |
| VPC | `jenkins-vpc` (10.0.0.0/16) |
| Subnet | `jenkins-subnet` (10.0.1.0/24), public, routed through an Internet Gateway |
| Security group | `jenkins-sg`, one group shared by all 3 instances |
| Inbound rules | TCP 22 (SSH), 80 (HTTP), 8080 (Jenkins) |
| Outbound rules | All traffic, all ports |
| Instances | `Jenkins-Ansible-Master` (t3.small), `Agent-1` (t2.micro), `Agent-2` (t2.micro) |
| AMI | Ubuntu 22.04 LTS |
| Elastic IPs | One per instance |

```
GitHub (push) --webhook--> Jenkins (Master) --Ansible/SSH--> Agent-1 (Apache2)
                                                         \-> Agent-2 (Nginx)
```

## Prerequisites

- AWS account with credentials configured (`aws sts get-caller-identity` works)
- Terraform installed (`terraform -version`)
- An EC2 key pair named `prt-key` (.pem) created in us-east-1
- A GitHub account

## Step 1: Provision infrastructure with Terraform

1. Create the key pair `prt-key` (EC2 -> Key pairs -> Create key pair, RSA, .pem).
2. Place `main.tf` in a folder (for example `tf-jenkins`).
3. Run:
   ```bash
   terraform init
   terraform apply -auto-approve
   ```
4. Note the Elastic IPs from the output:
   - `MASTER_IP` = Jenkins-Ansible-Master
   - `AGENT1_IP` = Agent-1
   - `AGENT2_IP` = Agent-2

## Step 2: Create the GitHub repository

1. Create a public repository `ansible-playbooks` with a README.
2. Add `playbook.yml` (installs Apache2 on the `apache` group and Nginx on the `nginx` group).
3. Commit to the `main` branch.

## Step 4: Install Ansible and Jenkins on the master (manual)

Copy the key to the master and connect:
```bash
chmod 400 prt-key.pem
scp -i prt-key.pem prt-key.pem ubuntu@MASTER_IP:~/
ssh -i prt-key.pem ubuntu@MASTER_IP
```

Install Ansible and Git:
```bash
sudo apt update
sudo apt install -y ansible git
```

Install Java 17 and Jenkins:
```bash
sudo apt install -y openjdk-17-jre
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins
sudo systemctl enable --now jenkins
```

## Step 5: Configure Ansible

Give the `jenkins` user access to the key:
```bash
sudo mkdir -p /var/lib/jenkins/.ssh
sudo cp ~/prt-key.pem /var/lib/jenkins/.ssh/
sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 700 /var/lib/jenkins/.ssh
sudo chmod 400 /var/lib/jenkins/.ssh/prt-key.pem
```

Edit the default inventory `/etc/ansible/hosts` (use the Elastic IPs):
```ini
[apache]
AGENT1_IP

[nginx]
AGENT2_IP

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=/var/lib/jenkins/.ssh/prt-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

Test connectivity and install Java on the agents (required by Jenkins agents):
```bash
sudo -u jenkins ansible all -m ping
sudo -u jenkins ansible all -b -m apt -a "name=openjdk-17-jre-headless update_cache=yes"
```

## Step 6: Set up the Jenkins dashboard and agents

1. Open `http://MASTER_IP:8080`.
2. Unlock with `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`.
3. Install suggested plugins and create the admin user.
4. Add the credential: Kind **SSH Username with private key**, ID `ubuntu-key`, username `ubuntu`, key = contents of `prt-key.pem`.
5. Manage Jenkins -> Nodes -> New Node, once per agent:
   - Name/label: `agent-1` / `agent-2`
   - Type: Permanent Agent, 1 executor
   - Remote root directory: `/home/ubuntu/jenkins`
   - Launch method: Launch agents via SSH, host = `AGENT1_IP` / `AGENT2_IP`
   - Credentials: `ubuntu-key`
   - Host Key Verification: Non verifying Verification Strategy
6. Confirm both nodes show as online.

## Step 7: Create the Jenkins job

1. New Item -> `ansible-deploy` -> Freestyle project.
2. Source Code Management: Git, repository URL of `ansible-playbooks`, branch `*/main`.
3. Build Triggers: **GitHub hook trigger for GITScm polling**.
4. Build step -> Execute shell:
   ```bash
   export ANSIBLE_HOST_KEY_CHECKING=False
   ansible-playbook -i /etc/ansible/hosts playbook.yml
   ```
5. Save and click **Build Now**. The console output should end with `Finished: SUCCESS`.

## Step 8: Create the GitHub webhook

GitHub repo -> Settings -> Webhooks -> Add webhook:

- Payload URL: `http://MASTER_IP:8080/github-webhook/`
- Content type: `application/json`
- Event: Just the push event
- Active: enabled

## Step 9: Verify

1. Edit `playbook.yml` in GitHub and commit. A Jenkins build should start automatically.
2. Open `http://AGENT1_IP` and confirm the Apache2 default page.
3. Open `http://AGENT2_IP` and confirm the Nginx welcome page.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Permission denied` on Ansible ping | Run with `sudo -u jenkins`; key permissions must be `400` |
| Agent will not connect | Install Java on the agent; paste the full key including BEGIN/END lines |
| Webhook does not trigger a build | Tick the GitHub hook trigger in the job; keep the trailing `/` in the payload URL |
| Jenkins is slow or crashes | Use at least t3.small for the master |

## Cleanup

```bash
terraform destroy -auto-approve
```
Also delete the `prt-key` key pair if it is no longer needed.

## Screenshots

Add your screenshots here:

- Terraform apply output with Elastic IPs
- EC2 instances list
- Security group inbound and outbound rules
- Ansible ping output
- Jenkins nodes page with both agents online
- Jenkins console output (`Finished: SUCCESS`)
- GitHub webhook delivery (green tick)
- Apache2 and Nginx pages in the browser

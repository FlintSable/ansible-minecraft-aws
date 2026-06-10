# ansible-minecraft-aws

This repo automates the Minecraft server setup from my CS312 Course Project Part 1.
The scripts create an EC2 instance, generate an Ansible inventory, configure the
Minecraft service, and verify that port `25565` is reachable with `nmap`.

I used AWS CLI scripts for provisioning and Ansible for configuration because that
matches the tools we used earlier in the course. GitHub Actions runs the same
pipeline on push for the extra credit part of the assignment. The final deploy
does not use the AWS Management Console except for copying Learner Lab credentials,
and I do not manually SSH into the EC2 instance or use EC2 `user_data`.

## Background

Part 1 was a manual AWS Minecraft server tutorial. For Part 2, I turned that
manual process into repeatable scripts. I kept the deployment on EC2 instead of
ECS/EKS because the original server was already a normal Linux `systemd` service,
and Ansible fits that workflow well.

The main behavior I needed to fix was shutdown. The old service started on boot,
but stopping it could interrupt Minecraft before it saved the world cleanly. This
version sends the Minecraft `stop` command through a named pipe before the service
exits.

## Requirements

Install these tools locally:

- AWS CLI v2
- Ansible 2.x
- `nmap` 7.x
- Git
- GitHub CLI (`gh`) 2.x, only needed for the GitHub Actions path
- `shellcheck`, only needed for development checks

On macOS with Homebrew:

```bash
brew install awscli ansible nmap gh shellcheck
```

This project was built for AWS Academy Learner Lab in `us-east-1`. Start the lab
and copy the AWS CLI credential block into `~/.aws/credentials`. The file should
have a profile with these three values:

```ini
[default]
aws_access_key_id = ...
aws_secret_access_key = ...
aws_session_token = ...
```

Check credentials with:

```bash
aws sts get-caller-identity
```

Project settings such as the region, security group name, key pair name, instance
type, and Minecraft port are in `_env.sh`.

## Pipeline Overview

```text
local terminal or GitHub Actions
        |
        v
001_provision.sh
  - creates/reuses the key pair, security group, and EC2 instance
        |
        v
002_inventory.sh
  - writes hosts.ini with the EC2 public IPv4 address
        |
        v
003_configure.sh
  - waits for EC2 to be ready
  - runs the Ansible playbook
  - verifies Minecraft with nmap
        |
        v
Minecraft on EC2
  - OpenJDK
  - Minecraft server jar
  - server.properties
  - systemd service with clean shutdown
```

`088_teardown.sh` removes the AWS resources when I am done.

## Running Locally

Run from the repository root after adding fresh Learner Lab credentials to
`~/.aws/credentials`:

```bash
./deploy.sh
```

`deploy.sh` runs:

```bash
./001_provision.sh
./002_inventory.sh
./003_configure.sh
```

Verify the server:

```bash
PUBLIC_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ansible-minecraft-aws" \
            "Name=tag:Role,Values=minecraft" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

nmap -sV -Pn -p T:25565 "$PUBLIC_IP"
```

Expected result:

```text
25565/tcp open  minecraft
```

The exact version string may vary, but `25565/tcp open` is the important part.

## Running With GitHub Actions

First sync the current Learner Lab credentials from `~/.aws/credentials` to GitHub
Secrets:

```bash
./000_sync_lab_creds.sh
```

Then push to `main`:

```bash
git push origin main
```

The workflow also supports manual runs:

```bash
gh workflow run deploy.yml
gh run watch
```

Learner Lab credentials expire, so I update `~/.aws/credentials` and rerun
`./000_sync_lab_creds.sh` after starting a new lab session.

## Connecting To Minecraft

After deployment, use the public IPv4 address printed by the scripts or listed in
`hosts.ini`.

1. Open Minecraft Java Edition.
2. Go to Multiplayer.
3. Add a server.
4. Use the EC2 public IPv4 address as the server address.
5. Join the server.

No port suffix is needed because Minecraft uses `25565` by default.

## Reboot And Shutdown Checks

To test restart after reboot:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=ansible-minecraft-aws" \
            "Name=tag:Role,Values=minecraft" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

aws ec2 reboot-instances --instance-ids "$INSTANCE_ID"
```

After about 90 seconds, run the `nmap` command again. The same public IPv4 should
still answer on port `25565`.

For the clean shutdown fix, the Ansible-managed `minecraft.service` uses
`ExecStop` to send `stop` to the Minecraft console before systemd finishes stopping
the service. In the demo, I check the service logs for Minecraft save messages.

## Teardown

Remove AWS resources when finished:

```bash
./088_teardown.sh
```

This terminates the EC2 instance, waits for it to finish, deletes the security
group, and deletes the AWS key pair. It does not delete my local SSH key from
`~/.ssh`.

## Sources

- CS312 Course Project Part 1 tutorial, used for the Minecraft version, paths,
  port, and original `systemd` service.
- CS312 Assignment 4 Ansible materials, used for the stage script pattern.
- Minecraft server download and EULA:
  <https://www.minecraft.net/en-us/download/server>
- AWS CLI EC2 command reference:
  <https://docs.aws.amazon.com/cli/latest/reference/ec2/>
- Ansible builtin module documentation:
  <https://docs.ansible.com/ansible/latest/collections/ansible/builtin/>
- GitHub Actions workflow syntax:
  <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax>

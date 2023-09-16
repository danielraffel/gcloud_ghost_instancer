#!/bin/bash

# Function for colored text used throughout the script
color_text() {
  case $1 in
    red)    printf "\033[0;31m$2\033[0m" ;;
    green)  printf "\033[0;32m$2\033[0m" ;;
    yellow) printf "\033[0;33m$2\033[0m" ;;
    blue)   printf "\033[0;34m$2\033[0m" ;;
    *)      printf "$2" ;;
  esac
}

# Initial setup prompt
# For more information about Google Cloud Free Tier micro instances, visit: https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits
initial_prompt() {
  # Print the initial message
  printf "This script will help you set up and run a Google Compute Engine E2-Micro virtual machine with Ghost.org installed.\n\nAn E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under Google Cloud's Always Free Tier, which means you won't incur any costs, subject to Google's terms and usage limits.\nLearn more: https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits\n"

  # Ask the user to proceed
  color_text green "\nDo you want to proceed? (y/n): "
  read -r setup_instance

  # If the user says no, exit the script
  if [ "$setup_instance" != "y" ]; then
    echo "No worries. Have a great day!"
    exit 0
  fi
}

# Check for gcloud CLI and install if not found. Installation proceeds without user interaction
# For more information about Google Cloud SDK, visit: https://cloud.google.com/sdk/docs
check_gcloud_install() {
  if ! command -v gcloud &> /dev/null; then
  # Explain to the user that gcloud SDK is required
  printf "gcloud SDK is required to proceed and could not be found.\nLearn more: https://cloud.google.com/sdk/docs\n"

  # Ask the user to proceed
  color_text green "\nDo you want to automatically download gcloud SDK and proceed? (y/n): "
    read -r install_gcloud
    if [ "$install_gcloud" = "y" ]; then
      echo "Installing gcloud..."

      # Download and run the CLI installer
      curl https://sdk.cloud.google.com | bash -s -- --disable-prompts

      # Update PATH and source bash completion
      export PATH=$PATH:$HOME/google-cloud-sdk/bin
      source "$HOME/google-cloud-sdk/completion.bash.inc"

      echo "gcloud installed and environment initialized."
    else
      echo "gcloud is required. Exiting."
      exit 1
    fi
  fi
}

# Check for gcloud in bashrc and zshrc
check_shell_setup() {
  if grep -q 'gcloud' ~/.bashrc || grep -q 'gcloud' ~/.zshrc; then
    :
  else
    echo "Setting up gCloud in .bashrc and .zshrc."
    echo 'alias ll="ls -l"' >> ~/.bashrc
    echo 'alias ll="ls -l"' >> ~/.zshrc
    source ~/.bashrc || source ~/.zshrc
  fi
}

# Use gcloud CLI to discover if the user has a project set up, and if not, authenticate and fetch it
authenticate_and_fetch_project() {
  PROJECT_ID=$(gcloud config get-value project 2> /dev/null)
  if [[ -z "$PROJECT_ID" ]]; then
    echo "No Google Cloud project set. Starting authentication..."
    gcloud auth login
    PROJECT_ID=$(gcloud config get-value project 2> /dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
      echo "Authentication failed or no project selected. Exiting."
      exit 1
    fi
  fi
}

# Prompt for zone where the user will setup their google VM instance and only show free zones
prompt_for_zone() {
  echo "\nTo create a free E2-Micro instance, you'll need to setup your VM in a colocation facility that supports free-tiers."
  echo " 1) Oregon: us-west1"
  echo " 2) Iowa: us-central1"
  echo " 3) South Carolina: us-east1"
  
  color_text green "\nSelect a zone that sounds like it's located closest to you: "
  read -r choice
  
  case "$choice" in
    1) ZONE="us-west1-a" ;;
    2) ZONE="us-central1-a" ;;
    3) ZONE="us-east1-a" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
  esac
}

# Automatically determines the Google Cloud region avoids the need to ask the user
get_region_from_zone() {
  REGION=$(echo $ZONE | sed 's/\(.*\)-.*/\1/')
}

# Main function to validate and conform the instance name according to GCP rules.
# Asks the user if they want to customize the VM name prefix using green-colored text.
# Offers the default name 'ghost' if no customization is desired.
# Constructs the full VM name in the format <CUSTOM_NAME>-ghost.
# Adjusts the custom name prefix to conform to GCP naming rules, eliminating invalid characters and case.
# Checks if a VM with the intended name already exists in the project; if so, prompts the user for a new name.
# Once a unique and GCP-compliant name is confirmed, informs the user of the final VM name.
name_instance() {
  while true; do
    # Asks the user if they want to customize the VM name prefix.
    printf "\nThis script will create a VM named 'ghost' you have the option to add a custom prefix (eg daniel-ghost)\n"
    read -r -p "$(color_text green "\nDo you want to customize your prefix? (y/n):") " CUSTOMIZE

    if [[ "$CUSTOMIZE" == "y" ]]; then
      # Prompts for a custom VM name prefix if customization is desired.
      read -r -p "$(color_text green "\nCustomize your prefix (e.g. 'yourprefix-ghost'):") " CUSTOM_NAME
    else
      # Uses the default 'ghost' if no customization is desired.
      CUSTOM_NAME=""
    fi

    # The full VM name will be in the format <CUSTOM_NAME>-ghost.
    if [[ -z "$CUSTOM_NAME" ]]; then
      INSTANCE_NAME="ghost"
    else
      # Adjusts the name to conform to GCP VM naming rules.
      ORIGINAL_NAME="$CUSTOM_NAME"
      CUSTOM_NAME=$(echo "$CUSTOM_NAME" | tr '[:upper:]' '[:lower:]')
      CUSTOM_NAME=${CUSTOM_NAME:0:62}
      CUSTOM_NAME=$(echo "$CUSTOM_NAME" | sed 's/[^a-z0-9-]//g')
      CUSTOM_NAME=$(echo "$CUSTOM_NAME" | sed 's/^-//;s/-*$//')
      INSTANCE_NAME="${CUSTOM_NAME}-ghost"
    fi

    # Informs the user if any adjustments were made to the name due to GCP rules.
    if [[ "$ORIGINAL_NAME" != "$CUSTOM_NAME" && -n "$ORIGINAL_NAME" ]]; then
      green_text "\nName adjusted to '$INSTANCE_NAME' due to GCP rules. Is this OK?"
      read -r -p $'\e[92m(y/n):\e[0m ' CONFIRM
      if [[ "$CONFIRM" == "n" ]]; then
        continue
      fi
    fi

    # Checks if the VM name already exists in the project; if so, prompts for a new name.
    EXISTING_INSTANCE=$(gcloud compute instances list --filter="name=($INSTANCE_NAME)" --format="get(name)")
    if [[ "$EXISTING_INSTANCE" == "$INSTANCE_NAME" ]]; then
      green_text "\nName '$INSTANCE_NAME' already exists. Choose another."
      continue
    fi

    # Once a unique and GCP-compliant name is confirmed, informs the user of the final VM name.
    color_text green "\nYour VM will be named: $INSTANCE_NAME"
    color_text yellow "\n\nYou can ignore the WARNING you're about see that you have selected a disk size of under [200GB] which may result in poor I/O performance. This is because the free tier is limited.\n\n"
    color_text yellow "\nYou can also ignore the WARNING you're about see that your disk size: '30 GB' is larger than image size: '10 GB'. Ubuntu Ubunto should automatically resize itself to use all the 30 GB you've allocated during the first boot.\n\n"
    break
  done
}


# This function performs necessary setup before creating a GCP instance.
# It sets up the Google Cloud project ID, fetches the default service account email,
# updates IAM roles, and prepares the region and zone information.
# Additionally, it retrieves stored passwords for the root and service accounts from Google Cloud Secret Manager.
prepare_instance_environment() {
  # Get the Project ID where the secret should reside
  SECRET_PROJECT_ID=$(gcloud config get-value project)

  # Fetch the Compute Engine default service account email and store it in a variable
  SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list --format='value(email)' --filter='displayName:"Compute Engine default service account"')

  # Update the IAM role for the Compute Engine default service account
  gcloud secrets add-iam-policy-binding service-account-password-$INSTANCE_NAME \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor"

  # Assume ZONE is already selected by the user and is a global variable
  REGION=$(echo $ZONE | sed 's/\(.*\)-.*/\1/')  # Set REGION based on ZONE

  # Fetch passwords from Google Cloud Secret Manager using the Project ID variable
  ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="root-password-$INSTANCE_NAME" --project=$SECRET_PROJECT_ID)
  SERVICE_ACCOUNT_PASSWORD=$(gcloud secrets versions access latest --secret="service-account-password-$INSTANCE_NAME" --project=$SECRET_PROJECT_ID)
}


# This function performs the following tasks:
# 1. Creates SSH keys for the root and service-account users on a specified GCP instance.
# 2. Retrieves these public keys and saves them into a temporary file.
# 3. Uploads these public keys to the project metadata so that future instances can use them.
# 4. Deletes the temporary file.
create_and_add_ssh_keys() {
  # Create SSH keys for root and service-account
  gcloud compute ssh $instance_name --username=root
  gcloud compute ssh $instance_name --username=service-account

  # Fetch public keys
  root_key=$(cat $HOME/.ssh/google_compute_engine.pub)
  # Checks if the $root_key string starts with "root:". If not (||), it prepends "root:" to the key.
  [[ $root_key == root:* ]] || root_key="root:${root_key}"

  service_account_key=$(cat $HOME/.ssh/service_account.pub)
  # Checks if the $service-account string starts with "service-account:". If not (||), it prepends "service-account:" to the key. 
  [[ $service_account_key == service-account:* ]] || service_account_key="service-account:${service_account_key}"

  # Concatenate keys into one string with usernames
  all_keys="root:${root_key}\nservice-account:${service_account_key}"

  # Save keys to a temporary file
  temp_file="${HOME}/temp_keys.txt"
  echo -e $all_keys > $temp_file

  # Add public keys to the project metadata
  gcloud compute project-info add-metadata --metadata-from-file ssh-keys=$temp_file

  # Clean up temporary file
  rm $temp_file
}


# Create a Google Cloud VM instance based on user input for zone and custom name.
# The VM will have the following configurations:
# - Machine type: e2-micro
# - Disk size: 30GB
# - Operating System: Ubuntu 22.04
# - Network Tags: Mail, custom name for HTTP and HTTPS firewall rules
#!/bin/bash


create_instance () {
  gcloud compute instances create $INSTANCE_NAME \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-project=ubuntu-os-cloud \
    --image-family=ubuntu-2204-lts \
    --boot-disk-size=30GB \
    --boot-disk-type=pd-standard \
    --tags=mail,http-server,https-server \
    --shielded-secure-boot=false \
    --shielded-vtpm=false \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --service-account service-account@$PROJECT_ID.iam.gserviceaccount.com \
    --metadata-from-file ssh-keys-for-root=$HOME/.ssh/root_key-${INSTANCE_NAME}.pub,ssh-keys-for-service-account=$HOME/.ssh/service_account_key-${INSTANCE_NAME}.pub \
    --metadata startup-script='#!/bin/bash
    # Variables
    INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
    PROJECT_ID=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")

    # Set root password
    ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="root-password-${INSTANCE_NAME}" --project=${PROJECT_ID})
    echo "root:${ROOT_PASSWORD}" | chpasswd

    # Create and set service-account password
    SERVICE_ACCOUNT_PASSWORD=$(gcloud secrets versions access latest --secret="service-account-password-${INSTANCE_NAME}" --project=${PROJECT_ID})
    useradd service-account
    echo "service-account:${SERVICE_ACCOUNT_PASSWORD}" | chpasswd
    usermod -aG sudo service-account

    # Make sure .ssh directories exist
    mkdir -p /root/.ssh
    mkdir -p /home/service-account/.ssh
    chown service-account:service-account /home/service-account/.ssh

    # Add authorized keys
    echo "$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/ssh-keys-for-root)" >> /root/.ssh/authorized_keys
    echo "$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/ssh-keys-for-service-account)" >> /home/service-account/.ssh/authorized_keys
    '

  # SSH Checker
  until gcloud compute ssh $INSTANCE_NAME --zone $ZONE --command "echo connected" &> /dev/null
  do
    echo "Waiting for SSH to be available..."
    sleep 5
  done
  echo "SSH is now available."

}

# ORIGINAL CREATE INSTANCE
# # Create a Google Cloud VM instance based on user input for zone and custom name.
# create_instance() {
#   # # Get the Project ID where the secret should reside
#   # SECRET_PROJECT_ID=$(gcloud config get-value project)

#   # # Fetch the Compute Engine default service account email and store it in a variable
#   # SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list --format='value(email)' --filter='displayName:"Compute Engine default service account"')

#   # # Update the IAM role for the Compute Engine default service account
#   # gcloud secrets add-iam-policy-binding service-account-password-$INSTANCE_NAME \
#   #   --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
#   #   --role="roles/secretmanager.secretAccessor"

#   # # Assume ZONE is already selected by the user and is a global variable
#   # REGION=$(echo $ZONE | sed 's/\(.*\)-.*/\1/')  # Set REGION based on ZONE
  
#   # Check and create daily backup schedule if it doesn't exist
#   EXISTING_POLICY=$(gcloud compute resource-policies list --filter="name='daily-backup-schedule'" --format="get(name)")

#   if [[ -z "$EXISTING_POLICY" ]]; then
#     # Adapt these flags based on your version of gcloud
#     gcloud compute resource-policies create snapshot-schedule daily-backup-schedule \
#       --region=$REGION \
#       --max-retention-days=30 \
#       --daily-schedule \
#       --start-time=21:00
#     echo "Daily backup schedule created."
#   else
#     echo "Daily backup schedule already exists."
#   fi

#   # # Fetch passwords from Google Cloud Secret Manager using the Project ID variable
#   # ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="root-password-$INSTANCE_NAME" --project=$SECRET_PROJECT_ID)
#   # SERVICE_ACCOUNT_PASSWORD=$(gcloud secrets versions access latest --secret="service-account-password-$INSTANCE_NAME" --project=$SECRET_PROJECT_ID)

#   # Experimental: Generate SSH key pair for service-account -- this seemed to work but lets try with gcp
#   # ssh-keygen -t rsa -f ~/.ssh/service_account_ssh -C service-account
#   # SERVICE_ACCOUNT_SSH_PUBLIC_KEY=$(cat ~/.ssh/service_account_ssh.pub)

#   # Create a new Google Compute Engine VM instance
#   # 1 Specify the zone where the VM will be created based on user selected free tier region
#   # 2 Set VM instance type to e2-micro
#   # 3 Set source project for the OS image to ubuntu-os-cloud
#   # 4 Set OS image to use ubuntu-2204-lts
#   # 5 Set disk size for the boot disk to 30GB (max free amount)
#   # 6 Set the type of disk to a Standard Persistent Disk
#   # 7 Add tags for ooutbound email access to support email list sending and open incoming http and https for web traffic
#   # 8 Enable full access to all Cloud APIs so the VM can access Google Cloud services like secret manager
#   # 9 Startup script to add service-account to the sudo group
#   # Run a startup script when the VM startsup
#   # 1 Fetch the name of the Google Compute Engine instance
#   # 2 Fetch the project ID of the Google Cloud project
#   # 3 Fetch the root password for this instance from Google Cloud Secret Manager
#   # 4 Change the root password
#   # 5 Fetch the service-account password for this instance from Google Cloud Secret Manager
#   # 6 Add a new user named 'service-account'
#   # 7 Set the password for the 'service-account'
#   # 8 Upload the public SSH key for the 'service-account' to Google Cloud project's SSH metadata to allow secure password-less SSH access in the future
#   # 9 Add 'service-account' to the sudo group to enable sudo access

#   while true; do
#       echo "Creating VM named '$INSTANCE_NAME'..."
#       if gcloud compute instances create $INSTANCE_NAME \
#     --zone=$ZONE \
#     --machine-type=e2-micro \
#     --image-project=ubuntu-os-cloud \
#     --image-family=ubuntu-2204-lts \
#     --boot-disk-size=30GB \
#     --boot-disk-type=pd-standard \
#     --tags=mail,http-server,https-server \
#     --scopes=https://www.googleapis.com/auth/cloud-platform \
#     --metadata-from-file ssh-keys="$HOME/.ssh/service_account_ssh.pub" \
#     --metadata startup-script='#!/bin/bash
# INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
# PROJECT_ID=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")
# ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="root-password-${INSTANCE_NAME}" --project=${PROJECT_ID})
# echo "root:${ROOT_PASSWORD}" | chpasswd
# SERVICE_ACCOUNT_PASSWORD=$(gcloud secrets versions access latest --secret="service-account-password-${INSTANCE_NAME}" --project=${PROJECT_ID})
# useradd service-account
# echo "service-account:${SERVICE_ACCOUNT_PASSWORD}" | chpasswd
# usermod -aG sudo service-account'; then
      
#     # If the VM creation was successful
#     printf "Your VM is successfully created with the name: "
#     color_text green "$INSTANCE_NAME"
#     printf "\n"
#      break
#     else
#       # If VM creation failed, ask the user if they want to try again
#       echo "Failed to create instance. Trying again may resolve the issue."
#       read -r -p "Try again? (y/n): " try_again
#       if [ "$try_again" != "y" ]; then
#         echo "Exiting."
#         exit 1
#       fi
#     fi
#   done
# }


# Wait for the instance to be running, then SSH into it.
# SSH keys are generated locally and saved in the ~/.ssh/ directory.
# The public key is uploaded to the Google Cloud project's SSH metadata to allow secure password-less SSH access in the future.
# For more information on SSH keys in Google Cloud, visit: https://cloud.google.com/compute/docs/connect/add-ssh-keys

# NEW
# ssh_instance () {
#   # Get the IP for the instance
#   INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
#   echo "Instance IP is: ${INSTANCE_IP}"

#   # Add the server's host key to the local known_hosts file
#   ssh-keyscan -H $INSTANCE_IP >> $HOME/.ssh/known_hosts

#   # Clear all loaded keys
#   ssh-add -D
  
#   # Load only the necessary keys
#   ssh-add $HOME/.ssh/service_account_key-${INSTANCE_NAME}
#   # ssh-add $HOME/.ssh/root_key-${INSTANCE_NAME}

#   # Debug: print the instance name and keys loaded into SSH agent
#   # echo "Instance name is: ${INSTANCE_NAME}"
#   # ssh-add -l
  
#   WAIT_TIME_SECONDS=5  # Adjust this to your preferred wait time

#   # Attempt SSH connection
#   ssh -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} service-account@$INSTANCE_IP

#   # Check the SSH exit code
#   SSH_EXIT_CODE=$?

#   # If SSH fails, wait for the specified time before retrying
#   if [ $SSH_EXIT_CODE -ne 0 ]; then
#       echo "SSH connection failed. Waiting for $WAIT_TIME_SECONDS seconds before retrying..."
#       sleep $WAIT_TIME_SECONDS
#   fi
# }


ssh_instance () {
    # Get the IP for the instance
    INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

    # Add the server's host key to the local known_hosts file
    ssh-keyscan -H $INSTANCE_IP >> $HOME/.ssh/known_hosts

    # Clear all loaded keys
    ssh-add -D

    # Load only the necessary keys
    ssh-add $HOME/.ssh/service_account_key-${INSTANCE_NAME}

    # Time to wait before retrying SSH
    WAIT_TIME_SECONDS=5

    # Maximum total retries
    MAX_TOTAL_RETRIES=20
    TOTAL_RETRIES=0

    while true; do
      if [ $TOTAL_RETRIES -ge $MAX_TOTAL_RETRIES ]; then
        echo "Maximum total retries reached, exiting..."
        exit 1
      fi

#       ssh -t -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} -o IdentitiesOnly=yes service-account@$INSTANCE_IP

        ssh -t -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} service-account@$INSTANCE_IP <<'ENDSSH'
        # Open a screen session
        screen -S ghost_install

        # Download the installer script from GitHub
        curl -O https://raw.githubusercontent.com/danielraffel/gcloud_ghost_instancer/main/install_on_server.sh

        # Make it executable and run it
        chmod +x install_on_server.sh
        ./install_on_server.sh
ENDSSH

      SSH_EXIT_CODE=$?

      if [ $SSH_EXIT_CODE -eq 0 ]; then
        echo "SSH connection and script execution successful."
        break
      else
        echo "SSH connection or script execution failed. Waiting for $WAIT_TIME_SECONDS seconds before retrying..."
        ssh-keygen -R $INSTANCE_IP
        sleep $WAIT_TIME_SECONDS
      fi

      TOTAL_RETRIES=$((TOTAL_RETRIES + 1))
    done
}

# LAST WORKING BIT MODIFIED
# ssh_instance () {
#     # Get the IP for the instance
#     INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

#     # Add the server's host key to the local known_hosts file
#     ssh-keyscan -H $INSTANCE_IP >> $HOME/.ssh/known_hosts

#     # Clear all loaded keys
#     ssh-add -D

#     # Load only the necessary keys
#     ssh-add $HOME/.ssh/service_account_key-${INSTANCE_NAME}

#     # If SSH fails wait 5 seconds and try again
#     WAIT_TIME_SECONDS=5


#     while true; do
#       ssh -t -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} -o IdentitiesOnly=yes service-account@$INSTANCE_IP <<'ENDSSH'
#         # Open a screen session
#         screen -S ghost_install

#         # Download the installer script from GitHub
#         curl -O https://raw.githubusercontent.com/danielraffel/gcloud_ghost_instancer/main/install_on_server.sh

#         # Make it executable and run it
#         chmod +x install_on_server.sh
#         ./install_on_server.sh
# ENDSSH

#       SSH_EXIT_CODE=$?

#       if [ $SSH_EXIT_CODE -eq 0 ]; then
#         echo "SSH connection and script execution successful."
#         break
#       else
#         echo "SSH connection or script execution failed. Waiting for $WAIT_TIME_SECONDS seconds before retrying..."
#         ssh-keygen -R $INSTANCE_IP
#         sleep $WAIT_TIME_SECONDS
#       fi
#     done
# }

#     while true; do
#       SSH_OUTPUT=$(ssh -t -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} -o IdentitiesOnly=yes service-account@$INSTANCE_IP <<'ENDSSH'
# 	  	# Open a screen session
#         screen -S ghost_install
		
# 		# Download the installer script from GitHub
#         curl -O https://raw.githubusercontent.com/danielraffel/gcloud_ghost_instancer/main/install_on_server.sh

# 		# Make it executable and run it
#         chmod +x install_on_server.sh
#         ./install_on_server.sh
# ENDSSH
# )

#       SSH_EXIT_CODE=$?

#       if [[ $SSH_EXIT_CODE -eq 0 ]]; then
#         echo "SSH connection and script execution successful."
#         break
#       else
#         echo "SSH connection or script execution failed. Waiting for $WAIT_TIME_SECONDS seconds before retrying..."

#         if [[ $SSH_OUTPUT == *"REMOTE HOST IDENTIFICATION HAS CHANGED!"* ]]; then
#           ssh-keygen -R $INSTANCE_IP
#         fi

#         sleep $WAIT_TIME_SECONDS
#       fi
#     done
# }


# #OLD - BUT SEEMED TO WORK at 743PM on FRI 9/15

# ssh_instance () {
#     # Get the IP for the instance
#     INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
#     # Add the server's host key to the local known_hosts file
#     ssh-keyscan -H $INSTANCE_IP >> $HOME/.ssh/known_hosts

#     # Clear all loaded keys
#     ssh-add -D

#     # Load only the necessary keys
#     ssh-add $HOME/.ssh/service_account_key-${INSTANCE_NAME}

#     # If SSH fails wait 5 seconds and try again
#     WAIT_TIME_SECONDS=5

#     while true; do
#       ssh -t -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} -o IdentitiesOnly=yes service-account@$INSTANCE_IP <<'ENDSSH'
#         # Open a screen session
#         screen -S ghost_install

#         # Download the installer script from GitHub
#         curl -O https://raw.githubusercontent.com/danielraffel/gcloud_ghost_instancer/main/install_on_server.sh

#         # Make it executable and run it
#         chmod +x install_on_server.sh
#         ./install_on_server.sh
# ENDSSH

#       SSH_EXIT_CODE=$?

#       if [ $SSH_EXIT_CODE -eq 0 ]; then
#         echo "SSH connection and script execution successful."
#         break
#       else
#         echo "SSH connection or script execution failed. Waiting for $WAIT_TIME_SECONDS seconds before retrying..."
#         ssh-keygen -R $INSTANCE_IP
#         sleep $WAIT_TIME_SECONDS
#       fi
#     done
# }


# ORIGINAL WAIT INSTANCE
# wait_and_ssh() {
#   while true; do
#     instance_status=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(status)' 2> /dev/null)
#     if [[ $instance_status == "RUNNING" ]]; then
#       break
#     elif [[ -z $instance_status ]]; then
#       echo "Instance not found or failed to create. Try again? (y/n)"
#       read -r try_again
#       if [ "$try_again" != "y" ]; then
#         echo "Exiting."
#         exit 1
#       fi
#     else
#       echo "Waiting for instance to be running..."
#       sleep 10
#     fi
#   done
#   # SSH in and start commands to setup the VM
# #  gcloud compute ssh $INSTANCE_NAME --zone $ZONE -- -t



# This function checks if Google Cloud Secret Manager is enabled for the project.
# If not, it enables the service and waits until the service is active.
# Secret Manager is used to store passwords in a secure location that can be accessed on the remote machine.
check_and_enable_secret_manager() {
  # Check if Secret Manager is enabled
  if gcloud services list --enabled | grep -q 'secretmanager.googleapis.com'; then
    echo "Secret Manager is already enabled. This script will use Secret Manager to securely store passwords in your account."
  else
    # Inform the user
    echo "Secret Manager is not enabled. Enabling now, this might take a moment..."

    # Enable the service
    gcloud services enable secretmanager.googleapis.com

    # Wait and check until the service is enabled
    until gcloud services list --enabled | grep -q 'secretmanager.googleapis.com'; do
      sleep 5  # wait for 5 seconds before checking again
    done

    echo "Secret Manager is now enabled. This script will use Secret Manager to securely store passwords in your account."
  fi
}

# Function to set passwords and store it in Google Cloud Secret Manager for secure access
generate_and_store_password() {
  # Generate a secure 32-character password
  password=$(openssl rand -base64 32)

  # Create a secret name based on the type and instance name
  secret_name="$1-password-$INSTANCE_NAME"

  # Create the secret in Google Cloud Secret Manager
  printf "%s" "$password" | gcloud secrets create "$secret_name" --data-file=-
  
  # If you want to overwrite an existing secret, use the following line instead
  # printf "%s" "$password" | gcloud secrets versions add "$secret_name" --data-file=-

  echo "Password generated and stored as $secret_name"
}

create_keys () { 
  # Generate SSH keys for root and service-account in the ssh directory
  ssh-keygen -t rsa -b 4096 -C "root" -f "$HOME/.ssh/root_key-${INSTANCE_NAME}"
  ssh-keygen -t rsa -b 4096 -C "service-account" -f "$HOME/.ssh/service_account_key-${INSTANCE_NAME}"

  # Fetch the Compute Engine default service account email and store it in a variable
  SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list --format='value(email)' --filter='displayName:"Compute Engine default service account"')

# Create GCP service account
gcloud iam service-accounts create service-account --display-name "service-account"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member serviceAccount:service-account@$PROJECT_ID.iam.gserviceaccount.com \
  --role roles/secretmanager.secretAccessor

# Update the IAM role for the Compute Engine default service account
gcloud secrets add-iam-policy-binding service-account-password-$INSTANCE_NAME \
--member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
--role="roles/secretmanager.secretAccessor"

}

# setup_vm_instance() {
#   # Inform the user that they will be asked to set a password for the root user
# #  color_text green "\nYou are about to be asked to set a password for the root user.\nMake sure to write this down. You'll need it again.\n\n"

#   # Secure your VM by setting a password for the root user
# #  sudo passwd

#   # Switch to root user and authenticate
# #  su

#   # Update Linux
#  # apt update && apt -y upgrade

#   # Create a service_account user that will manage software installs, etc and grant it sudo
#  # adduser service_account && usermod -aG sudo service_account

#   # Switch to service_account
# #  su - service-account

# # This script is intended to run on the remote server
# # It will fetch the name of the instance it's running on, even if that instance name is already known to the local environment.

# # 1. Fetch the name of the instance this script is running on
# #INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
# #echo "Debug: INSTANCE_NAME=$INSTANCE_NAME"

# # 2. Use the instance name to fetch the password for 'service_account' from Google Cloud Secret Manager
# #SERVICE_ACCOUNT_PASSWORD=$(gcloud secrets versions access latest --secret="service-account-password-$INSTANCE_NAME")
# #echo "Debug: INSTANCE_NAME=$SERVICE_ACCOUNT_PASSWORD"

# # 3. Switch to the 'service_account' user using the fetched password
# #echo $SERVICE_ACCOUNT_PASSWORD | su - service-account

# #debug
# #echo "You are signed in"
# cat /etc/passwd | awk -F: '{ print $1 }'


# }

# OLD INSTALLER
# install_ghost_dependencies() {
#   # Install Nginx and open the firewall
#   sudo apt install -y nginx && sudo ufw allow 'Nginx Full'

#   # Install NodeJS
#   sudo apt update
#   sudo apt install -y ca-certificates curl gnupg
#   sudo mkdir -p /etc/apt/keyrings
#   curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
#   NODE_MAJOR=18
#   echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
#   sudo apt update
#   sudo apt install nodejs -y
#   sudo npm install -g npm@latest

#   # Install MySQL
#   sudo apt install -y mysql-server

#   # Clean up
#   sudo apt -y autoremove

#   # Start MySQL in modified mode
#   sudo systemctl set-environment MYSQLD_OPTS="--skip-networking --skip-grant-tables"
#   sudo systemctl start mysql.service

#   # Prepare MySQL commands
#   echo "flush privileges;" > commands.sql
#   echo "USE mysql;" >> commands.sql
#   echo "ALTER USER 'root'@'localhost' identified BY '$root_password';" >> commands.sql
#   echo "quit;" >> commands.sql

#   # Run MySQL commands
#   sudo mysql -u root < commands.sql

#   # Remove SQL commands file
#   rm commands.sql

#   # Unset root password variable for security
#   unset root_password

#   # Restart MySQL and switch to production mode
#   sudo systemctl unset-environment MYSQLD_OPTS
#   sudo systemctl revert mysql
#   sudo killall -u mysql
#   sudo systemctl restart mysql.service
#   sudo mysql_secure_installation

#   # Turn off MySQL’s performance schema to reduce its memory usage
#   echo -e "\n[mysqld]\nperformance_schema=0" | sudo tee -a /etc/mysql/my.cnf

#   # Restart MySQL
#   sudo /etc/init.d/mysql restart
# }

  # Hardcoded IPs for testing and jumping into wait_and_ssh to see if it works without setting up lots of servers
  debug_vm() {
    INSTANCE_NAME="light-ghost"
    ZONE="us-west1-a"

# Get the IP for the instance
INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

# SSH into the remote machine

    ssh -t -i ~/.ssh/gcp danielraffel@$INSTANCE_IP << "ENDSSH"
    journalctl -f
ENDSSH


#ssh -T -i ~/.ssh/gcp danielraffel@$INSTANCE_IP
#    gcloud compute ssh "$INSTANCE_NAME" --zone "$ZONE" -t
#  gcloud compute ssh "$INSTANCE_NAME" --zone "$ZONE" -t --command "$(declare -f set_password_on_remote); set_password_on_remote"
#gcloud compute ssh "$INSTANCE_NAME" --zone "$ZONE" --command "$(declare -f set_password_on_remote); set_password_on_remote"

# gcloud compute ssh $INSTANCE_NAME --zone=$ZONE



# SSH into the remote machine and run the function
#ssh username@remote_machine 'bash -s' < <(declare -f set_sudo_password; echo set_sudo_password)
#vi /var/log/startup-script.log
  }





# Function to retrieve a stored password and set it for a user
set_password_on_remote() {
  password=$(gcloud secrets versions access latest --secret="root-password-$INSTANCE_NAME")
  echo -e "$password\n$password" | sudo passwd root
}







# Main function that orchestrates script behavior
  main() {
    # Check if the first argument is "debug_vm" and if so, run the debug_vm function
    if [ "$1" == "debug_vm" ]; then
#      check_and_enable_secret_manager
#      generate_and_store_password "root"
      debug_vm
#      set_sudo_password
#      set_password_on_remote
      setup_vm_instance
      install_ghost_dependencies
      exit 0
    fi

    # Start the script by running the initial prompt (when not in debug mode)
    # initial_prompt
    # check_gcloud_install
    # check_shell_setup
    # authenticate_and_fetch_project
    # prompt_for_zone
    # get_region_from_zone
    # name_instance
    # create_instance
    # wait_and_ssh
    # setup_vm_instance
    # install_ghost_dependencies

#new order
    initial_prompt
    check_gcloud_install
    check_shell_setup
    authenticate_and_fetch_project
    prompt_for_zone
    get_region_from_zone
    name_instance
    check_and_enable_secret_manager
    generate_and_store_password "root"
    generate_and_store_password "service-account"
    generate_and_store_password "mysql"
    create_keys
#    prepare_instance_environment
#    create_and_add_ssh_keys
    create_instance
    ssh_instance
#    wait_and_ssh
#    setup_vm_instance
    install_ghost_dependencies
}

main "$@"








# Your main or debug function can call this function like so:

# Generate and store root password
generate_and_store_password "root"

# Generate and store MySQL password
generate_and_store_password "mysql"

# Generate and store service account password
generate_and_store_password "service_account"



# SSH into the remote machine and execute the set_password_on_remote function
execute_on_remote() {
  gcloud compute ssh "$INSTANCE_NAME" --zone "$ZONE" --command "$(declare -f set_password_on_remote); set_password_on_remote"
}
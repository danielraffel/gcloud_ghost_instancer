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

  # Write setup variables to a file for use when resizing the instance in downgrade_instance
  echo "INSTANCE_NAME=$INSTANCE_NAME" > $HOME/temp_vars.sh
  echo "ZONE=$ZONE" >> $HOME/temp_vars.sh
  echo "REGION=$REGION" >> $HOME/temp_vars.sh
}


# Create a Google Cloud VM instance based on user input for zone and custom name.
# The VM will have the following configurations:
# - Machine type: e2-micro
# - Disk size: 30GB
# - Operating System: Ubuntu 22.04
# - Network Tags: Mail, custom name for HTTP and HTTPS firewall rules
#!/bin/bash

create_instance () {
# Retrieve the secret from Google Secret Manager
mysql_password=$(gcloud secrets versions access latest --secret="$secret_name")

# Explain that you're gonna be asked for your mysql password in a bit
color_text red "Ghost install will ask for this MySQL password, copy it now:\n$mysql_password"
color_text green "\n\nPress any key to continue"
read -n 1 -s -r

# Check if the firewall rule for sending email exists
if gcloud compute firewall-rules describe allow-outgoing-2525 &>/dev/null; then
    echo "\nFirewall rule allow-outgoing-2525 already exists."
else
    # Create the firewall rule
    gcloud compute firewall-rules create allow-outgoing-2525 \
        --direction=EGRESS \
        --network=default \
        --action=ALLOW \
        --rules=tcp:2525 \
        --destination-ranges=0.0.0.0/0 \
        --target-tags=mail
fi

# Create the instance
  gcloud compute instances create $INSTANCE_NAME \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --image-project=ubuntu-os-cloud \
    --image-family=ubuntu-2204-lts \
    --boot-disk-size=30GB \
    --boot-disk-type=pd-standard \
    --tags=mail,http-server,https-server \
    --no-shielded-secure-boot \
    --no-shielded-vtpm \
    --no-shielded-integrity-monitoring \
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
        # screen -S ghost_install

        # Download the installer script from GitHub
        curl -O https://raw.githubusercontent.com/danielraffel/gcloud_ghost_instancer/main/install_on_server.sh

        # Make it executable and run it
        chmod +x install_on_server.sh
        bash -i ./install_on_server.sh
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

downgrade_instance() {

  # Source the variables from temp_vars.sh to complete the next few commands
  source $HOME/temp_vars.sh

  # stop the e2-medium instance
  gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE

  # change the machine type from e2-medium to e2-micro
  gcloud compute instances set-machine-type $INSTANCE_NAME --zone=$ZONE --machine-type=e2-micro

  # start the e2-micro
  gcloud compute instances start $INSTANCE_NAME --zone=$ZONE

  # Create a Standard tier static IP address
  gcloud compute addresses create $STATIC_IP_NAME --region=$REGION --network-tier=STANDARD

  # Add the static IP address to the instance
  gcloud compute instances add-access-config $INSTANCE_NAME --zone=$ZONE --access-config-name="External NAT" --address $STATIC_IP_NAME

  # Get the static IP address
  STATIC_IP=$(gcloud compute addresses describe $STATIC_IP_NAME --region=$REGION --format='get(address)')

  # Delete the temporary variables file
  rm $HOME/temp_vars.sh

  # SSH into the remote machine
  # ssh -t -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} service-account@$INSTANCE_IP 'ghost ls; exit'

  # Share machine IP address
  color_text green "\nYour VM is running at: $STATIC_IP"

  # Remove the host key for the instance from the local known_hosts file in case it was previously added
  ssh-keygen -R 35.233.251.221

  # Add the static IP address to Known Hosts file
  ssh-keyscan -H $STATIC_IP >> $HOME/.ssh/known_hosts

  # SSH into the remote machine at the static address
  ssh -t -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} service-account@$STATIC_IP << "ENDSSH"
  # Open a screen session
  screen -S ghost_install
  cd /var/www/ghost
  ghost ls
ENDSSH
  
}

# Optional debug function used during development.
# Assumes you've run the script and setup a server with keys and want to access a hardcoded VM IP and jump directly into ssh_instance.
# To run execute "sh gcloud_ghost_instancer.sh debug_vm" 
debug_vm() {
    INSTANCE_NAME="yourprefix-ghost"
    ZONE="us-west1-a"

  # Get the IP for the instance
  INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

  # SSH into the remote machine
  ssh -t -i ~/.ssh/gcp yourname@$INSTANCE_IP << "ENDSSH"
  journalctl -f
ENDSSH
}


# Main function that orchestrates script behavior
  main() {
    # Check if the first argument is "debug_vm" and if so, run the debug_vm function
    if [ "$1" == "debug_vm" ]; then
      debug_vm
      setup_vm_instance
      exit 0
    fi

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
    create_instance
    ssh_instance
    downgrade_instance
}

main "$@"